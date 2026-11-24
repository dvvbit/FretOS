import AppKit
import Combine
import FretOSCore

/// Snapshot of what the guitar is doing, for the UI.
struct LiveState: Equatable {
    var active: Set<GuitarInput> = []
    var whammyDelta = 0
    var tiltDelta = 0
}

/// App-side owner of the guitar, settings and key output. UI binds to this.
@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    @Published private(set) var status: EngineStatus = .noGuitar
    @Published private(set) var live = LiveState()
    @Published private(set) var seen: Set<GuitarInput> = []   // inputs pressed at least once
    @Published private(set) var permissionGranted = Permission.granted
    /// The user clicked ALLOW this session: next step is to reopen FretOS.
    @Published private(set) var askedForPermission = false
    @Published var capturing: GuitarInput? { didSet { refreshGate() } }
    @Published var settings: Settings {
        didSet {
            store.settings = settings
            let s = settings
            core.withProcessor { $0.bindings = s.bindings; $0.tuning = s.tuning }
            if oldValue.launchAtLogin != s.launchAtLogin { LaunchAtLogin.set(s.launchAtLogin) }
            refreshGate()
        }
    }

    var enabled: Bool {
        get { core.enabled }
        set { core.enabled = newValue; objectWillChange.send(); refreshStatus() }
    }

    private let store = SettingsStore()
    private let core: EngineCore
    private let device = GuitarDevice()
    private var timer: Timer?
    private nonisolated let liveUpdateQueued = ManagedAtomicBool()

    private init() {
        let s = store.settings
        settings = s
        core = EngineCore(processor: InputProcessor(tuning: s.tuning, bindings: s.bindings), sink: CGKeySink())
    }

    func start() {
        core.permission = Permission.granted
        device.pendingRelease = { [core] in
            var pending = false
            core.withProcessor { pending = $0.hasPendingRelease }
            return pending
        }
        device.onReport = { [weak self, core] r in
            core.handle(r, now: ProcessInfo.processInfo.systemUptime)
            self?.queueLiveUpdate()
        }
        device.onTick = { [core] in core.handle(nil, now: ProcessInfo.processInfo.systemUptime) }
        device.onConnectionChange = { [weak self, core] connected in
            core.setConnected(connected)
            self?.queueLiveUpdate()
        }
        device.start()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshGate() } }
        poll()
    }

    // MARK: - Actions

    func bind(_ input: GuitarInput, to key: UInt16?) {
        settings.bindings[input] = key
        capturing = nil
    }
    func askForPermission() {
        Permission.request()
        Permission.openSettings()
        askedForPermission = true
    }
    func resetToDefaults() { settings.bindings = Preset.cloneHeroDefault.bindings }
    func recalibrate() { core.withProcessor { $0.recalibrate() } }
    func setTuning(_ change: (inout Tuning) -> Void) { change(&settings.tuning) }

    /// Snapshot/preview only: show a fixed state without a guitar.
    func previewLive(_ l: LiveState, status s: EngineStatus, seen: Set<GuitarInput>) {
        live = l; status = s; self.seen = seen
    }

    // MARK: - Internals

    private func poll() {
        let granted = Permission.granted
        if granted != permissionGranted { permissionGranted = granted }
        core.permission = granted
        core.cloneHeroRunning = NSWorkspace.shared.runningApplications.contains {
            FocusGate.isCloneHero($0.localizedName) || FocusGate.isCloneHero($0.bundleIdentifier)
        }
        refreshGate()
    }

    private func refreshGate() {
        let front = NSWorkspace.shared.frontmostApplication
        // Never send keys while the user is choosing a key in our own window.
        core.gateOpen = capturing == nil && FocusGate.allows(
            frontmostAppName: front?.localizedName, bundleID: front?.bundleIdentifier,
            onlyWhenCloneHeroFront: settings.onlyWhenCloneHeroFront)
        refreshStatus()
    }

    private func refreshStatus() {
        let s = core.status
        if s != status { status = s }
    }

    /// Called from the USB thread; coalesces UI updates to at most one per main-loop turn.
    nonisolated private func queueLiveUpdate() {
        guard !liveUpdateQueued.testAndSet() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            MainActor.assumeIsolated { self?.publishLive() }
        }
    }

    private func publishLive() {
        liveUpdateQueued.value = false
        var next = LiveState()
        core.withProcessor { p in
            next.active = p.active
            if let rest = p.rest {
                next.whammyDelta = abs(Int(p.lastReport.whammy) - Int(rest.whammy))
                next.tiltDelta = abs(Int(p.lastReport.tilt) - Int(rest.tilt))
            }
        }
        if !core.connected { next = LiveState() }
        if next != live { live = next }
        let newlySeen = next.active.subtracting(seen)
        if !newlySeen.isEmpty { seen.formUnion(newlySeen) }
        refreshStatus()
    }
}
