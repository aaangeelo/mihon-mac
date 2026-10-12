// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MihonMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MihonMac", targets: ["MihonMac"])],
    targets: [
        .executableTarget(name: "MihonMac"),
    ]
)
