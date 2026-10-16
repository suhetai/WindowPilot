// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowPilot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WindowPilot", targets: ["WindowPilot"])],
    targets: [
        .executableTarget(name: "WindowPilot")
    ]
)
