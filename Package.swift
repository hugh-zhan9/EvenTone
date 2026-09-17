// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EvenTone",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EvenTone", targets: ["EvenTone"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "EvenTone", dependencies: ["AudioDSP"],
                          linkerSettings: [.linkedFramework("SwiftUI"), .linkedFramework("CoreAudio"), .linkedFramework("ServiceManagement"), .linkedFramework("AVFAudio")])
    ]
)
