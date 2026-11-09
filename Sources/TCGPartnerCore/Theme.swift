import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Temas de color de la app, inspirados en los tipos de Pokémon.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, psychic, fire, water, grass, lightning, darkness, dragon, fairy

    static let key = "app.theme"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .psychic: "Psíquico"
        case .fire: "Fuego"
        case .water: "Agua"
        case .grass: "Planta"
        case .lightning: "Eléctrico"
        case .darkness: "Siniestro"
        case .dragon: "Dragón"
        case .fairy: "Hada"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .psychic: "sparkles"
        case .fire: "flame.fill"
        case .water: "drop.fill"
        case .grass: "leaf.fill"
        case .lightning: "bolt.fill"
        case .darkness: "moon.fill"
        case .dragon: "tornado"
        case .fairy: "star.fill"
        }
    }

    /// Color principal (botones, selección, enlaces). `nil` = el color de acento de macOS.
    var accent: Color? {
        switch self {
        case .system: nil
        case .psychic: Color(red: 0.58, green: 0.33, blue: 0.93)
        case .fire: Color(red: 0.96, green: 0.40, blue: 0.16)
        case .water: Color(red: 0.16, green: 0.52, blue: 0.95)
        case .grass: Color(red: 0.20, green: 0.70, blue: 0.36)
        case .lightning: Color(red: 0.93, green: 0.68, blue: 0.05)
        case .darkness: Color(red: 0.36, green: 0.38, blue: 0.62)
        case .dragon: Color(red: 0.05, green: 0.62, blue: 0.62)
        case .fairy: Color(red: 0.93, green: 0.36, blue: 0.64)
        }
    }

    /// Segundo color del degradado de fondo.
    var secondary: Color? {
        switch self {
        case .system: nil
        case .psychic: Color(red: 0.93, green: 0.36, blue: 0.64)
        case .fire: Color(red: 0.93, green: 0.68, blue: 0.05)
        case .water: Color(red: 0.05, green: 0.62, blue: 0.62)
        case .grass: Color(red: 0.62, green: 0.80, blue: 0.20)
        case .lightning: Color(red: 0.96, green: 0.40, blue: 0.16)
        case .darkness: Color(red: 0.58, green: 0.33, blue: 0.93)
        case .dragon: Color(red: 0.85, green: 0.62, blue: 0.18)
        case .fairy: Color(red: 0.58, green: 0.33, blue: 0.93)
        }
    }

    /// Para pintar muestras del tema «Sistema».
    var swatch: Color { accent ?? .accentColor }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "app.appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    #if os(macOS)
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    #endif

    /// Para `.preferredColorScheme` (iPhone). `nil` = la del sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Fondo de las vistas principales: el del sistema con un degradado suave del tema arriba.
struct AppBackground: View {
    @AppStorage(AppTheme.key) private var theme = AppTheme.system

    var body: some View {
        ZStack(alignment: .top) {
            Color.windowBackground
            if let accent = theme.accent, let secondary = theme.secondary {
                LinearGradient(colors: [accent.opacity(0.16), secondary.opacity(0.06), .clear],
                               startPoint: .topLeading, endPoint: .init(x: 0.7, y: 0.45))
            }
        }
        .ignoresSafeArea()
    }
}
