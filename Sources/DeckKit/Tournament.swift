import Foundation

/// Formato del torneo, como aparece en la hoja oficial de Play! Pokémon.
public enum GameFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, expanded

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard: "Estándar"
        case .expanded: "Expandido"
        }
    }

    public var englishTitle: String {
        switch self {
        case .standard: "Standard"
        case .expanded: "Expanded"
        }
    }
}

/// División de edad de Play! Pokémon.
public enum AgeDivision: String, CaseIterable, Codable, Sendable {
    case junior, senior, masters

    public var title: String {
        switch self {
        case .junior: "Junior"
        case .senior: "Senior"
        case .masters: "Masters"
        }
    }

    /// Temporada de Play! Pokémon en curso. Cada temporada empieza en julio y lleva
    /// el nombre del año en que termina (octubre de 2026 → temporada 2027).
    public static func season(on date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        return calendar.component(.month, from: date) >= 7 ? year + 1 : year
    }

    /// División según el año de nacimiento: en la temporada T, Junior nació en T-12 o después,
    /// Senior entre T-16 y T-13, y Masters en T-17 o antes.
    public static func forBirthDate(_ birthDate: Date, on date: Date = Date(), calendar: Calendar = .current) -> AgeDivision {
        let season = season(on: date, calendar: calendar)
        let born = calendar.component(.year, from: birthDate)
        if born >= season - 12 { return .junior }
        if born >= season - 16 { return .senior }
        return .masters
    }
}
