import Foundation

/// Iconos de Pokémon como los de Limitless (`https://r2.limitlesstcg.net/pokemon/gen9/<slug>.png`).
public enum PokemonIcon {
    public static func url(slug: String) -> URL {
        URL(string: "https://r2.limitlesstcg.net/pokemon/gen9/\(slug).png")!
    }

    /// Nombre de carta o de Pokémon → nombre del icono.
    /// «Dragapult ex» → `dragapult`, «Alolan Ninetales» → `ninetales-alola`,
    /// «Mega Lucario ex» → `lucario-mega`, «Wellspring Mask Ogerpon ex» → `ogerpon-wellspring`,
    /// «Ethan's Typhlosion» → `typhlosion`, «Mr. Mime» → `mr-mime`, «Farfetch'd» → `farfetchd`.
    public static func slug(_ raw: String) -> String {
        var name = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespaces)
        var forms: [String] = []

        // Sufijos de mecánica de carta.
        for suffix in [" ex", " gx", " vmax", " vstar", " v-union", " v", " break", " ◇", " prime", " lv.x", " star"]
        where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        // Prefijos que no forman parte del Pokémon: «Radiant», «Shining», «Ethan's», «Team Rocket's».
        for prefix in ["Radiant ", "Shining ", "Dark ", "Light "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        if let range = name.range(of: #"^(?:Team )?[A-Z][\w.]*'s "#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        // Formas que van al final del nombre del icono.
        let prefixForms: [(String, String?)] = [
            ("Alolan ", "alola"), ("Galarian ", "galar"), ("Hisuian ", "hisui"), ("Paldean ", "paldea"),
            ("Mega ", "mega"), ("Bloodmoon ", "bloodmoon"), ("Origin Forme ", "origin"),
            ("Wellspring Mask ", "wellspring"), ("Hearthflame Mask ", "hearthflame"),
            ("Cornerstone Mask ", "cornerstone"), ("Teal Mask ", nil),
            ("Rapid Strike ", "rapid-strike"), ("Single Strike ", "single-strike"),
            ("Shadow Rider ", "shadow"), ("Ice Rider ", "ice"), ("Black ", "black"), ("White ", "white"),
        ]
        for (prefix, form) in prefixForms where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            if let form { forms.append(form) }
        }
        // «Mega Charizard X» → charizard-mega-x.
        if forms.contains("mega"), let last = name.split(separator: " ").last, ["X", "Y"].contains(last) {
            name = String(name.dropLast(2))
            forms.append(last.lowercased())
        }

        let base = name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .joined(separator: "-")
        return ([base] + forms).filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// Nombres a probar en orden: el completo y, si tiene varias palabras, solo la primera
    /// («Alakazam Fantasma» → `alakazam-fantasma`, `alakazam`).
    public static func candidates(_ raw: String) -> [String] {
        let full = slug(raw)
        guard !full.isEmpty else { return [] }
        let first = slug(String(raw.split(separator: " ").first ?? ""))
        return first.isEmpty || first == full ? [full] : [full, first]
    }

    /// Combina los dos campos del selector de iconos en la lista a guardar.
    /// Si antes no había iconos propios (se veían los heredados) y escribes solo el segundo,
    /// el primero se rellena con el heredado: así «Alakazam» (heredado) + «Dusknoir» queda en los dos.
    /// Devuelve también el primer campo, por si hubo que rellenarlo.
    public static func combine(first: String, second: String, previous: [String], inherited: [String])
        -> (first: String, names: [String]) {
        var first = first.trimmingCharacters(in: .whitespaces)
        let second = second.trimmingCharacters(in: .whitespaces)
        if first.isEmpty, !second.isEmpty, previous.isEmpty, let base = inherited.first,
           base.caseInsensitiveCompare(second) != .orderedSame {
            first = base
        }
        return (first, [first, second].filter { !$0.isEmpty })
    }

    /// Separa un nombre de mazo en Pokémon para los iconos: «Alakazam / Dusknoir», «Charizard ex + Pidgeot ex».
    public static func split(_ deckName: String) -> [String] {
        deckName.components(separatedBy: CharacterSet(charactersIn: "/+,&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { $0 }
    }
}
