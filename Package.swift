// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Alterna",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Alterna",
            path: "Sources/Alterna",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
