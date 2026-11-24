import CoreGraphics
import FretOSCore

/// Posts real keyboard events system-wide.
final class CGKeySink: KeySink {
    private let source = CGEventSource(stateID: .hidSystemState)
    func post(_ e: KeyEvent) {
        CGEvent(keyboardEventSource: source, virtualKey: e.keyCode, keyDown: e.down)?.post(tap: .cghidEventTap)
    }
}
