// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Meilink",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Meilink",
            path: "client/macos-native",
            exclude: ["Info.plist", "Resources"]
        )
    ]
)
