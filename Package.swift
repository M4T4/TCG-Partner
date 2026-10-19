// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TCGPartner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeckKit"),
        .executableTarget(name: "TCGPartner", dependencies: ["DeckKit"]),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"], resources: [.copy("Fixtures")]),
    ]
)
