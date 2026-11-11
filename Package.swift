// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TCGPartner",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Para la app de iPhone (proyecto de Xcode), que usa este paquete.
        .library(name: "TCGPartnerCore", targets: ["TCGPartnerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        // Lógica pura, sin interfaz.
        .target(name: "DeckKit"),
        // Datos, sincronización y toda la interfaz SwiftUI, compartidos por Mac e iPhone.
        .target(name: "TCGPartnerCore", dependencies: [
            "DeckKit",
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
        // App de Mac: ventana, menús y ciclo de vida.
        .executableTarget(name: "TCGPartner", dependencies: ["TCGPartnerCore"]),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"], resources: [.copy("Fixtures")]),
    ]
)
