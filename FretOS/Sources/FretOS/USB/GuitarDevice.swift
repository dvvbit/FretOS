import CLibUSB
import Foundation
import FretOSCore

/// Talks to the guitar over raw USB on its own background thread.
/// Finds it (retrying every second), reads input reports, and recovers on unplug/replug.
/// Callbacks fire on the USB thread so key events go out with no main-thread delay.
final class GuitarDevice: @unchecked Sendable {
    var onReport: ((RawGuitarReport) -> Void)?
    var onTick: (() -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    /// Asked before each read: while a debounced release is pending, poll fast so it goes out on time.
    var pendingRelease: () -> Bool = { false }

    private var thread: Thread?
    private let stopFlag = ManagedAtomicBool()
    private let infoLock = NSLock()
    private var _connectedName: String?
    /// e.g. "Guitar Hero X-plorer (1430:4748)" while a guitar is open, for problem reports.
    var connectedName: String? {
        infoLock.lock(); defer { infoLock.unlock() }; return _connectedName
    }
    private func setConnectedName(_ n: String?) { infoLock.lock(); _connectedName = n; infoLock.unlock() }

    func start() {
        guard thread == nil else { return }
        stopFlag.value = false
        let t = Thread { [weak self] in self?.run() }
        t.name = "FretOS.USB"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() { stopFlag.value = true; thread = nil }

    // MARK: - Loop

    private func run() {
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else { NSLog("FretOS: libusb_init failed"); return }
        defer { libusb_exit(ctx) }

        while !stopFlag.value {
            guard let (handle, epIn) = open(ctx) else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            setConnectedName(describe(handle))
            onConnectionChange?(true)
            readLoop(handle, epIn)
            libusb_release_interface(handle, 0)
            libusb_close(handle)
            setConnectedName(nil)
            onConnectionChange?(false)
        }
    }

    private func readLoop(_ handle: OpaquePointer, _ epIn: UInt8) {
        var buf = [UInt8](repeating: 0, count: 32)
        while !stopFlag.value {
            var got: Int32 = 0
            let timeout: UInt32 = pendingRelease() ? 2 : 250
            let rc = libusb_interrupt_transfer(handle, epIn, &buf, Int32(buf.count), &got, timeout)
            if rc == LIBUSB_ERROR_TIMEOUT.rawValue { onTick?(); continue }
            if rc != 0 { return }  // unplugged or failed: caller closes and goes back to searching
            if let report = RawGuitarReport.parse(Array(buf.prefix(Int(got)))) { onReport?(report) }
            else { onTick?() }
        }
    }

    private func open(_ ctx: OpaquePointer?) -> (OpaquePointer, UInt8)? {
        var list: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(ctx, &list)
        guard count > 0, let list else { return nil }
        defer { libusb_free_device_list(list, 1) }
        for i in 0..<Int(count) {
            guard let dev = list[i], isGuitar(dev) else { continue }
            var opened: OpaquePointer?
            guard libusb_open(dev, &opened) == 0, let handle = opened else { continue }
            _ = libusb_set_configuration(handle, 1)
            _ = libusb_set_auto_detach_kernel_driver(handle, 1)
            guard libusb_claim_interface(handle, 0) == 0,
                  let (epIn, epOut) = endpoints(libusb_get_device(handle)) else {
                libusb_close(handle); continue
            }
            if let epOut {  // ring light → player 1 (cosmetic; ignore failures)
                var led: [UInt8] = [0x01, 0x03, 0x06]
                var sent: Int32 = 0
                _ = libusb_interrupt_transfer(handle, epOut, &led, 3, &sent, 100)
            }
            return (handle, epIn)
        }
        return nil
    }

    /// Product name (if the guitar reports one) plus vendor:product ID.
    private func describe(_ handle: OpaquePointer) -> String {
        var desc = libusb_device_descriptor()
        guard libusb_get_device_descriptor(libusb_get_device(handle), &desc) == 0 else { return "unknown" }
        let ids = String(format: "%04x:%04x", desc.idVendor, desc.idProduct)
        var buf = [UInt8](repeating: 0, count: 128)
        let n = desc.iProduct == 0 ? 0 : libusb_get_string_descriptor_ascii(handle, desc.iProduct, &buf, Int32(buf.count))
        guard n > 0 else { return ids }
        let name = String(decoding: buf.prefix(Int(n)), as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? ids : "\(name) (\(ids))"
    }

    /// The X-plorer by ID, or any wired Xbox 360 device whose interface 0 says it's a guitar.
    private func isGuitar(_ dev: OpaquePointer) -> Bool {
        var desc = libusb_device_descriptor()
        guard libusb_get_device_descriptor(dev, &desc) == 0 else { return false }
        if SupportedDevices.ids.contains(where: { $0.vendor == desc.idVendor && $0.product == desc.idProduct }) { return true }
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        guard libusb_get_config_descriptor(dev, 0, &config) == 0, let config else { return false }
        defer { libusb_free_config_descriptor(config) }
        guard config.pointee.bNumInterfaces > 0, config.pointee.interface[0].num_altsetting > 0 else { return false }
        let alt = config.pointee.interface[0].altsetting[0]
        let extra = alt.extra.map { Array(UnsafeBufferPointer(start: $0, count: Int(alt.extra_length))) } ?? []
        return SupportedDevices.isXInputGuitar(interfaceClass: alt.bInterfaceClass, subClass: alt.bInterfaceSubClass,
                                               protocol: alt.bInterfaceProtocol, extra: extra)
    }

    /// Interrupt IN/OUT endpoints of interface 0.
    private func endpoints(_ dev: OpaquePointer?) -> (UInt8, UInt8?)? {
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        guard libusb_get_active_config_descriptor(dev, &config) == 0, let config else { return nil }
        defer { libusb_free_config_descriptor(config) }
        guard config.pointee.bNumInterfaces > 0, config.pointee.interface[0].num_altsetting > 0 else { return nil }
        let alt = config.pointee.interface[0].altsetting[0]
        var epIn: UInt8?, epOut: UInt8?
        for i in 0..<Int(alt.bNumEndpoints) {
            let ep = alt.endpoint[i]
            guard ep.bmAttributes & 0x03 == UInt8(LIBUSB_TRANSFER_TYPE_INTERRUPT.rawValue) else { continue }
            if ep.bEndpointAddress & 0x80 != 0 { epIn = epIn ?? ep.bEndpointAddress }
            else { epOut = epOut ?? ep.bEndpointAddress }
        }
        guard let epIn else { return nil }
        return (epIn, epOut)
    }
}

/// Minimal lock-protected Bool (avoids pulling in swift-atomics).
final class ManagedAtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    /// Sets to true; returns the previous value.
    func testAndSet() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let old = _value; _value = true; return old
    }
}
