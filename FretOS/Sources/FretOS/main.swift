import Foundation
import FretOSCore

if CommandLine.arguments.contains("--probe") {
    // Dev aid (mirrors xplorer.py --debug): print what the guitar sends, send no keys.
    let device = GuitarDevice()
    var last: Set<GuitarInput>? = nil
    device.onConnectionChange = { print($0 ? "connected" : "disconnected") }
    device.onReport = { r in
        if r.buttons != last {
            last = r.buttons
            let names = GuitarInput.allCases.filter(r.buttons.contains).map(\.rawValue)
            print(names, "whammy=\(r.whammy) tilt=\(r.tilt)")
        }
    }
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Probing for guitar… (Ctrl+C to quit)")
    device.start()
    dispatchMain()
} else if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshot.run(to: CommandLine.arguments[i + 1]) }
} else {
    FretOSApp.main()
}
