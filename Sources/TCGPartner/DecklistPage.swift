import DeckKit
import SwiftUI

/// Datos del jugador que se imprimen en la hoja.
struct PlayerInfo {
    var name: String
    var playerID: String
    var birthDate: Date?
    var format: GameFormat

    var division: AgeDivision? { birthDate.map { AgeDivision.forBirthDate($0) } }
}

/// Tipografías para la hoja impresa. Todas son del sistema, así que siempre están disponibles.
enum PrintTypography: String, CaseIterable, Identifiable {
    case modern, rounded, technical, editorial

    var id: Self { self }

    var title: String {
        switch self {
        case .modern: "Moderna"
        case .rounded: "Redondeada"
        case .technical: "Técnica"
        case .editorial: "Editorial"
        }
    }

    var detail: String {
        switch self {
        case .modern: "SF Pro · limpia y neutra"
        case .rounded: "SF Rounded · amable, estilo app"
        case .technical: "SF Mono · columnas alineadas"
        case .editorial: "New York · serif clásica"
        }
    }

    var design: Font.Design {
        switch self {
        case .modern: .default
        case .rounded: .rounded
        case .technical: .monospaced
        case .editorial: .serif
        }
    }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case letter, a4

    var id: Self { self }

    var title: String {
        switch self {
        case .letter: "Carta"
        case .a4: "A4"
        }
    }

    /// Tamaño en puntos (1/72 de pulgada).
    var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595, height: 842)
        }
    }
}

/// Idioma de la hoja impresa (independiente del idioma de la app).
enum PrintLanguage: String, CaseIterable, Identifiable {
    case spanish, english

    var id: Self { self }

    var title: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .spanish ? "es_MX" : "en_US")
    }

    func pick(_ spanish: String, _ english: String) -> String {
        self == .spanish ? spanish : english
    }

    /// «14 mar 1995» / «Mar 14, 1995».
    func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    func cards(_ count: Int) -> String {
        count == 1 ? pick("1 carta", "1 card") : pick("\(count) cartas", "\(count) cards")
    }

    func section(_ section: DeckSection) -> String {
        pick(section.title, section.exportHeader)
    }

    func format(_ format: GameFormat) -> String {
        pick(format.title, format.englishTitle)
    }
}

struct PrintOptions {
    var language: PrintLanguage = .spanish
    var typography: PrintTypography = .modern
    var paper: PaperSize = .letter
    var color = true
    var includeNotes = true
}

/// La hoja de la lista lista para imprimir: se usa tanto en la vista previa como para generar el PDF.
struct DecklistPage: View {
    let deck: Deck
    let player: PlayerInfo
    let options: PrintOptions
    var printedOn = Date()

    private static let margin: CGFloat = 36

    private var parsed: ParsedDeck { deck.parsed }
    private var lang: PrintLanguage { options.language }
    private var notes: String { deck.notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var accent: Color { options.color ? Color(red: 0.36, green: 0.23, blue: 0.68) : .black }
    private var accentGradient: LinearGradient {
        options.color
            ? LinearGradient(colors: [Color(red: 0.20, green: 0.26, blue: 0.66), Color(red: 0.58, green: 0.22, blue: 0.70)],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.black], startPoint: .leading, endPoint: .trailing)
    }
    private let ink = Color(white: 0.1)
    private let muted = Color(white: 0.45)
    private let hairline = Color(white: 0.82)
    private let zebra = Color(white: 0.955)

    /// Alto de fila: se ajusta para que la lista quepa siempre en una página.
    private var rowHeight: CGFloat {
        let left = parsed.entries(in: .pokemon).count + parsed.entries(in: .energy).count
        let right = parsed.entries(in: .trainer).count
        let rows = CGFloat(max(left + 3, right + 1, 1)) // cabeceras de tabla y separación cuentan como filas
        let fixed: CGFloat = 250 + (options.includeNotes ? 95 : 0)
        let available = options.paper.size.height - Self.margin * 2 - fixed
        return min(17, max(10, available / rows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            playerFields
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: rowHeight) {
                    table(.pokemon)
                    table(.energy)
                }
                table(.trainer)
            }
            if options.includeNotes {
                notesBox
            } else {
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(Self.margin)
        .frame(width: options.paper.size.width, height: options.paper.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
        .fontDesign(options.typography.design)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Partes

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TCG - Partner")
                        .font(.system(size: 38, weight: .black))
                        .tracking(-0.8)
                        .foregroundStyle(accentGradient)
                    Text("DECKLIST · POKÉMON TCG")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(deck.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text("\(lang.format(player.format)) · \(lang.cards(parsed.totalCount))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(muted)
                }
            }
            Capsule().fill(accentGradient).frame(height: 3)
        }
    }

    private var playerFields: some View {
        HStack(spacing: 8) {
            field(lang.pick("Jugador", "Player name"), player.name).frame(maxWidth: .infinity)
            field("Player ID", player.playerID).frame(width: 92)
            field(lang.pick("Fecha de nacimiento", "Date of birth"), player.birthDate.map(lang.date) ?? "")
                .frame(width: 112)
            field(lang.pick("División", "Age division"), player.division?.title ?? "").frame(width: 82)
            field(lang.pick("Formato", "Format"), lang.format(player.format)).frame(width: 80)
        }
    }

    /// Recuadro con etiqueta; si el valor está vacío queda espacio para escribirlo a mano.
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 6.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).stroke(hairline, lineWidth: 0.8))
    }

    private func table(_ section: DeckSection) -> some View {
        let cards = parsed.entries(in: section)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(lang.section(section).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                Spacer()
                Text("\(parsed.count(in: section))")
                    .font(.system(size: 9.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(accent))
            }
            .padding(.bottom, 5)
            Rectangle().fill(accent).frame(height: 1.2)
            HStack(spacing: 6) {
                Text(lang.pick("CANT.", "QTY")).frame(width: 24, alignment: .trailing)
                Text(lang.pick("NOMBRE", "NAME")).frame(maxWidth: .infinity, alignment: .leading)
                Text("SET").frame(width: 30, alignment: .leading)
                Text(lang.pick("Nº", "NO.")).frame(width: 30, alignment: .trailing)
            }
            .font(.system(size: 6, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(muted)
            .frame(height: 14)
            if cards.isEmpty {
                Text("—")
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
            }
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                HStack(spacing: 6) {
                    Text("\(card.count)")
                        .font(.system(size: rowFont, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                    Text(card.printName)
                        .font(.system(size: rowFont))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(card.setCode ?? "")
                        .font(.system(size: rowFont - 1, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 30, alignment: .leading)
                    Text(card.number ?? "")
                        .font(.system(size: rowFont - 1, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(height: rowHeight)
                .background(index.isMultiple(of: 2) ? zebra : Color.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var rowFont: CGFloat { min(10, max(7.5, rowHeight * 0.6)) }

    private var notesBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(lang.pick("NOTAS", "NOTES"))
                .font(.system(size: 6.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(accent)
            Text(notes)
                .font(.system(size: 9))
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(minHeight: 85, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).stroke(hairline, lineWidth: 0.8))
    }

    private var footer: some View {
        HStack {
            Text("Total: \(lang.cards(parsed.totalCount)) · "
                 + DeckSection.allCases.map { "\(parsed.count(in: $0)) \(lang.section($0))" }.joined(separator: " · "))
            Spacer()
            Text("\(lang.pick("Generado con", "Generated with")) TCG - Partner · \(lang.date(printedOn))")
        }
        .font(.system(size: 7, weight: .medium))
        .foregroundStyle(muted)
    }
}
