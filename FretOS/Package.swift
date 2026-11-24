// swift-tools-version:5.9
import PackageDescription

let vendorLib = Context.packageDirectory + "/Vendor/libusb/lib"

let package = Package(
    name: "FretOS",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FretOSCore"),
        .systemLibrary(name: "CLibUSB", path: "Sources/CLibUSB"),
        .executableTarget(
            name: "FretOS",
            dependencies: ["FretOSCore", "CLibUSB"],
            resources: [.copy("Resources")],
            linkerSettings: [
                .unsafeFlags(["-L", vendorLib,
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-rpath", "-Xlinker", vendorLib]),
            ]
        ),
        .testTarget(name: "FretOSCoreTests", dependencies: ["FretOSCore"]),
    ]
)
