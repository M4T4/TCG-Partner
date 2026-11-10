import Charts
import DeckKit
import SwiftUI

/// «61.5 %»; «—» sin partidas.
func percentText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(.percent.precision(.fractionLength(0...1)))
}

/// Verde si ganas más de lo que pierdes, rojo si menos, azul en medio.
func winRateColor(_ rate: Double?) -> Color {
    guard let rate else { return .secondary }
    if rate >= 0.55 { return .green }
    if rate < 0.45 { return .red }
    return .blue
}

/// Contenedor con título para las secciones del dashboard.
struct Panel<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                accessory
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(16)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.controlBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.6)))
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    var detail: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.controlBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.6)))
    }
}

struct WinRateBar: View {
    let rate: Double?

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(winRateColor(rate)).frame(width: 52 * (rate ?? 0))
            }
            .frame(width: 52, height: 5)
            Text(percentText(rate))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(winRateColor(rate))
                .frame(width: 48, alignment: .leading)
        }
    }
}

extension Placement {
    /// Oro, plata, bronce; el resto con el color de la app.
    var color: Color {
        switch medal {
        case 1: Color(red: 0.95, green: 0.72, blue: 0.13)
        case 2: Color(red: 0.62, green: 0.66, blue: 0.72)
        case 3: Color(red: 0.80, green: 0.50, blue: 0.24)
        default: .accentColor
        }
    }

    var symbol: String { medal == nil ? "flag.checkered" : "medal.fill" }
}

/// «🥉 3.º de 64 · Top 4» para tarjetas y cabeceras.
struct PlacementBadge: View {
    let placement: Placement

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: placement.symbol)
            Text(placement.text).monospacedDigit()
            if let title = placement.title {
                Text("· \(title)")
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(placement.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(placement.color.opacity(0.15)))
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.4), lineWidth: 0.8))
    }
}

struct StatusBadge: View {
    let status: DeckStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 5, height: 5)
            Text(status.badge)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.color.opacity(0.12)))
    }
}

/// Icono de un arquetipo: sus Pokémon (como en Limitless) o un círculo de color con la inicial.
struct ArchetypeIcon: View {
    let archetype: Archetype?
    var size: CGFloat = 18

    var body: some View {
        if let archetype, !archetype.iconNames.isEmpty {
            PokemonIcons(names: archetype.iconNames, size: size * 1.25)
        } else {
            Circle()
                .fill(archetype?.color.color ?? .gray)
                .overlay(
                    Text(String(archetype?.name.prefix(1) ?? "?").uppercased())
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                )
                .frame(width: size, height: size)
        }
    }
}

struct PieSlice: Identifiable {
    let label: String
    let value: Double
    let color: Color
    /// Iconos de Pokémon para la leyenda.
    var icons: [String] = []
    var id: String { label }
}

/// Gráfica de pastel con el sprite pixel de cada rebanada dentro de ella (como en Limitless).
struct PieChart: View {
    let slices: [PieSlice]
    /// Dato principal arriba de la gráfica (por ejemplo, el win rate) y su detalle.
    var title: String?
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.title2.weight(.bold)).monospacedDigit()
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            chart
        }
    }

    private var chart: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value(slice.label, slice.value), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .chartOverlay { _ in
            GeometryReader { geo in
                sliceIcons(in: geo.size)
            }
            .allowsHitTesting(false)
        }
    }

    /// Un icono dentro de cada rebanada que tenga espacio para él.
    private func sliceIcons(in size: CGSize) -> some View {
        let total = slices.reduce(0) { $0 + $1.value }
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var start = 0.0
        let placed: [(id: String, name: String, point: CGPoint, size: CGFloat)] = slices.compactMap { slice in
            defer { start += slice.value }
            guard total > 0, let name = slice.icons.first else { return nil }
            let fraction = slice.value / total
            // Una rebanada que ocupa todo el pastel lleva el icono en el centro y más grande.
            if fraction > 0.999 { return (slice.id, name, center, radius * 0.8) }
            let iconSize = radius * (fraction > 0.25 ? 0.5 : 0.4)
            let distance = radius * 0.6
            // El arco a esa distancia debe ser al menos tan largo como el icono.
            guard fraction * 2 * .pi * distance >= iconSize * 0.9 else { return nil }
            // Swift Charts empieza arriba (12 en punto) y avanza en el sentido del reloj.
            let angle = (start + slice.value / 2) / total * 2 * .pi - .pi / 2
            return (slice.id, name, CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle)), iconSize)
        }
        return ZStack {
            ForEach(placed, id: \.id) { item in
                PokemonIconView(name: item.name, size: item.size)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .position(item.point)
            }
        }
    }
}

/// Fila de leyenda: punto de color, nombre y valor.
struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    var icons: [String] = []

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            if !icons.isEmpty { PokemonIcons(names: icons, size: 22) }
            Text(label).lineLimit(1)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.callout)
    }
}

extension MatchKind {
    var symbol: String {
        switch self {
        case .online: "globe"
        case .inPerson: "person.2"
        }
    }
}

extension MatchResult {
    var color: Color {
        switch self {
        case .win: .green
        case .loss: .red
        case .tie: .gray
        }
    }

    var symbol: String {
        switch self {
        case .win: "trophy.fill"
        case .loss: "xmark"
        case .tie: "equal"
        }
    }

    var short: String {
        switch self {
        case .win: "V"
        case .loss: "D"
        case .tie: "E"
        }
    }
}

extension MatchRecord {
    /// «Victoria vs Ana (Gardevoir ex)».
    var headline: String {
        let rival = [opponent.isEmpty ? nil : opponent,
                     opponentArchetype.isEmpty ? nil : (opponent.isEmpty ? opponentArchetype : "(\(opponentArchetype))")]
            .compactMap { $0 }.joined(separator: " ")
        return rival.isEmpty ? result.title : "\(result.title) vs \(rival)"
    }
}

/// Dos o más tarjetas lado a lado; en iPhone, una debajo de otra.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content
    @CompactWidth private var compact

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: .top, spacing: spacing) { content }
        }
    }
}

/// Hoja con un formulario y sus botones: en Mac, Eliminar / Cancelar / Confirmar abajo; en iPhone,
/// Cancelar y Confirmar en la barra superior y Eliminar en la barra inferior.
struct EditorSheet<Content: View>: View {
    let title: String
    let confirmLabel: String
    var canConfirm = true
    /// `nil` oculta el botón Eliminar (p. ej. al crear).
    var onDelete: (() -> Void)?
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmLabel, action: onConfirm).disabled(!canConfirm)
                    }
                    if let onDelete {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Eliminar", role: .destructive, action: onDelete)
                                .foregroundStyle(.red)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            content
            HStack {
                if let onDelete {
                    Button("Eliminar", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
            .padding(16)
        }
        #endif
    }
}

/// Etiqueta de botón que siempre ocupa una línea: si el texto no cabe (iPhone, letra grande)
/// usa la versión corta y, si aún no cabe, encoge un poco la letra.
struct OneLineLabel: View {
    let title: String
    var short: String? = nil
    let systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage).lineLimit(1)
            Label(short ?? title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Fila de iPhone para tablas de resultados: icono, nombre y detalle en dos líneas, y el win rate
/// a la derecha. Nunca parte palabras aunque la letra del sistema sea grande.
struct CompactStatRow<Icon: View>: View {
    let title: String
    let detail: String
    let rate: Double?
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(percentText(rate))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(winRateColor(rate))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(winRateColor(rate)).frame(width: 44 * (rate ?? 0))
                }
                .frame(width: 44, height: 4)
            }
            .fixedSize()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// «18 partidas · 10-8» o «Sin partidas».
func gamesDetail(_ stats: MatchStats) -> String {
    guard stats.total > 0 else { return "Sin partidas" }
    return "\(stats.total) \(stats.total == 1 ? "partida" : "partidas") · \(stats.record)"
}
