// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dockstep",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Dockstep", path: "Sources/Dockstep")
    ]
)
