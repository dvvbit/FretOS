import Foundation

public protocol KeySink: AnyObject {
    func post(_ e: KeyEvent)
}

public enum EngineStatus: Equatable, Sendable {
    case noGuitar, needsPermission, ready, playing, paused, off

    public var text: String {
        switch self {
        case .noGuitar: return "PLUG IN YOUR GUITAR"
        case .needsPermission: return "ALLOW KEYSTROKES →"
        case .ready: return "READY — OPEN CLONE HERO"
        case .playing: return "PLAYING"
        case .paused: return "PAUSED (Clone Hero not in front)"
        case .off: return "OFF"
        }
    }
}

/// Decides when processed key events actually get posted.
/// Always feeds the processor (so the UI can show live input), but only posts while
/// enabled + permission granted + focus gate open. Whenever any of those turns off,
/// or the guitar disconnects, every held key is released immediately.
/// Thread-safe: reports arrive on the USB thread, flags change on the main thread.
public final class EngineCore: @unchecked Sendable {
    public let processor: InputProcessor
    private let sink: KeySink
    private let lock = NSRecursiveLock()

    private var _enabled = true, _permission = false, _gateOpen = false, _connected = false
    private var _cloneHeroRunning = false

    public init(processor: InputProcessor, sink: KeySink) {
        self.processor = processor
        self.sink = sink
    }

    public var enabled: Bool { get { locked { _enabled } } set { setFlag { _enabled = newValue } } }
    public var permission: Bool { get { locked { _permission } } set { setFlag { _permission = newValue } } }
    public var gateOpen: Bool { get { locked { _gateOpen } } set { setFlag { _gateOpen = newValue } } }
    public var cloneHeroRunning: Bool { get { locked { _cloneHeroRunning } } set { locked { _cloneHeroRunning = newValue } } }
    public var connected: Bool { locked { _connected } }

    public func setConnected(_ value: Bool) {
        locked {
            if !value { for e in processor.releaseAll() where canSend { sink.post(e) } }
            if value && !_connected { processor.recalibrate() }
            _connected = value
        }
    }

    public var status: EngineStatus {
        locked {
            if !_connected { return .noGuitar }
            if !_permission { return .needsPermission }
            if !_enabled { return .off }
            if _gateOpen { return .playing }
            return _cloneHeroRunning ? .paused : .ready
        }
    }

    /// A report from the guitar, or nil for a timer tick.
    public func handle(_ report: RawGuitarReport?, now: TimeInterval) {
        locked {
            let events = processor.process(report, now: now)
            if canSend { events.forEach(sink.post) }
            else { _ = processor.releaseHeld() }  // nothing was posted, so nothing is held
        }
    }

    /// Run a closure against the processor under the engine lock (bindings/tuning changes).
    public func withProcessor(_ body: (InputProcessor) -> Void) { locked { body(processor) } }

    // MARK: - private

    private var canSend: Bool { _enabled && _permission && _gateOpen }

    private func setFlag(_ change: () -> Void) {
        locked {
            let before = canSend
            change()
            if before && !canSend {
                // Release what Clone Hero thinks is held; anything still held on the guitar
                // gets pressed fresh once output resumes.
                processor.releaseHeld().forEach(sink.post)
            }
        }
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}
