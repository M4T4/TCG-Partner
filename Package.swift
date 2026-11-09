// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TCGPartner",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        .target(name: "DeckKit"),
        .executableTarget(name: "TCGPartner", dependencies: [
            "DeckKit",
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"], resources: [.copy("Fixtures")]),
    ]
)
