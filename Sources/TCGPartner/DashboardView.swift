import DeckKit
import SwiftUI

enum StatsScope: String, CaseIterable, Identifiable {
    case season, all
    var id: Self { self }
}

/// Acciones que el dashboard pide a la ventana (abrir hojas, navegar).
struct AppActions {
    var select: (SidebarItem) -> Void
    var newDeck: () -> Void
    var logMatch: (_ deckID: UUID?) -> Void
    /// Registrar una partida de un tipo concreto (PTCG Live o presencial).
    var logMatchOfKind: (_ deckID: UUID?, _ kind: MatchKind) -> Void
    var editArchetype: (Archetype?) -> Void
    var editEvent: (TournamentEvent?) -> Void
    /// Abre la ficha completa de una partida.
    var showMatch: (UUID) -> Void
    /// Abre el formulario con una partida ya rellenada (p. ej. evento y ronda).
    var newMatch: (MatchRecord) -> Void
}

struct DashboardView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    let actions: AppActions

    @AppStorage("dashboard.scope") private var scope = StatsScope.season
    @State private var showAllArchetypes = false

    private var season: Int { AgeDivision.season(on: Date()) }

    private var scopedMatches: [MatchRecord] {
        scope == .season ? matches.items.inSeason(season) : matches.items
    }

    private var analytics: Analytics {
        Analytics(decks: decks, archetypes: archetypes, matches: scopedMatches)
    }

    private var upcomingEvents: [TournamentEvent] {
        events.items.filter { $0.isUpcoming() }.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                let analytics = analytics
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statCards(analytics)
                    if proxy.size.width > 1020 {
                        HStack(alignment: .top, spacing: 20) {
                            mainColumn(analytics)
                            sideColumn(analytics).frame(width: 330)
                        }
                    } else {
                        mainColumn(analytics)
                        sideColumn(analytics)
                    }
                }
                .padding(28)
                .frame(maxWidth: 1280)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppBackground())
    }

    // MARK: - Cabecera y tarjetas

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard").font(.largeTitle.bold())
                Text("\(scope == .season ? "Temporada \(season)" : "Todo el historial") · \(scopedMatches.count == 1 ? "1 partida" : "\(scopedMatches.count) partidas")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Periodo", selection: $scope) {
                Text(verbatim: "Temporada \(season)").tag(StatsScope.season)
                Text("Todo").tag(StatsScope.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { actions.logMatch(nil) } label: {
                Label("Registrar partida", systemImage: "plus.circle")
            }
            Button(action: actions.newDeck) {
                Label("Nuevo mazo", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func statCards(_ analytics: Analytics) -> some View {
        let stats = scopedMatches.stats
        let previous = matches.items.inSeason(season - 1).stats.winRate
        let delta: String? = {
            guard scope == .season, let now = stats.winRate, let previous else { return nil }
            let points = (now - previous) * 100
            return "\(points >= 0 ? "+" : "")\(points.formatted(.number.precision(.fractionLength(1)))) pts vs temporada anterior"
        }()
        let active = decks.decks.filter { $0.currentStatus != .retired }
        let next = upcomingEvents.first
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            StatCard(title: "Win rate", value: percentText(stats.winRate), valueColor: winRateColor(stats.winRate),
                     detail: delta ?? (stats.total > 0 ? "Récord \(stats.record)" : "Sin partidas registradas"),
                     symbol: "chart.line.uptrend.xyaxis")
            StatCard(title: "Arquetipo más usado", value: analytics.mostUsedArchetype?.name ?? "—",
                     detail: analytics.mostUsedArchetype.map { "\($0.stats.total) partidas" } ?? "Registra partidas para verlo",
                     symbol: "flame")
            StatCard(title: "Mazos activos", value: "\(active.count)",
                     detail: "\(active.filter { $0.currentStatus == .ready }.count) listos para torneo",
                     symbol: "rectangle.stack")
            StatCard(title: "Próximo evento",
                     value: next.map { $0.startDate.formatted(.dateTime.weekday(.abbreviated).day()).capitalized } ?? "—",
                     detail: next.map { "\($0.name) · \($0.startDate.formatted(date: .omitted, time: .shortened))" } ?? "Sin eventos próximos",
                     symbol: "calendar")
        }
    }

    // MARK: - Columna principal

    private func mainColumn(_ analytics: Analytics) -> some View {
        VStack(spacing: 20) {
            archetypesPanel(analytics)
            decksPanel(analytics)
            eventResultsPanel
            recentPanel
        }
        .frame(maxWidth: .infinity)
    }

    private func archetypesPanel(_ analytics: Analytics) -> some View {
        let rows = analytics.archetypePerformance
        let visible = showAllArchetypes ? rows : Array(rows.prefix(6))
        return Panel(title: "Arquetipos", subtitle: "Tus arquetipos con sus carpetas, mazos y resultados") {
            Button { actions.editArchetype(nil) } label: {
                Label("Arquetipo", systemImage: "plus")
            }
        } content: {
            if rows.isEmpty {
                emptyState("Crea un arquetipo (por ejemplo «Alakazam») y relaciónale carpetas de mazos.",
                           button: "Nuevo arquetipo") { actions.editArchetype(nil) }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    GridRow {
                        Text("Arquetipo")
                        Text("Carpetas").gridColumnAlignment(.trailing)
                        Text("Mazos").gridColumnAlignment(.trailing)
                        Text("Partidas").gridColumnAlignment(.trailing)
                        Text("Win rate")
                        Text("")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    ForEach(visible) { row in
                        Divider()
                        GridRow {
                            HStack(spacing: 8) {
                                ArchetypeIcon(archetype: row.archetype, size: 22)
                                Text(row.name).fontWeight(.medium).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.folderCount)").monospacedDigit().foregroundStyle(.secondary)
                            Text("\(row.deckCount)").monospacedDigit().foregroundStyle(.secondary)
                            Text("\(row.stats.total)").monospacedDigit()
                            WinRateBar(rate: row.stats.winRate)
                            Menu {
                                if let archetype = row.archetype {
                                    Button("Abrir") { actions.select(.archetype(archetype.id)) }
                                    Button("Editar…") { actions.editArchetype(archetype) }
                                }
                                Button("Registrar partida…") { actions.logMatch(nil) }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let archetype = row.archetype { actions.select(.archetype(archetype.id)) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, rows.count > 6 ? 0 : 12)
                if rows.count > 6 {
                    Divider()
                    Button(showAllArchetypes ? "Mostrar menos" : "Ver todos los arquetipos (\(rows.count))") {
                        showAllArchetypes.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
            }
        }
    }

    private func decksPanel(_ analytics: Analytics) -> some View {
        let rows = analytics.deckPerformance.filter { $0.deck.currentStatus != .retired }.prefix(6)
        return Panel(title: "Mazos que más juego", subtitle: "Resultados y estado de tus listas") {
            EmptyView()
        } content: {
            if rows.isEmpty {
                emptyState("Pega una lista de Limitless para crear tu primer mazo.", button: "Nuevo mazo", action: actions.newDeck)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    GridRow {
                        Text("Mazo")
                        Text("Arquetipo")
                        Text("Partidas").gridColumnAlignment(.trailing)
                        Text("V - D")
                        Text("Win rate")
                        Text("Estado").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    ForEach(Array(rows)) { row in
                        Divider()
                        GridRow {
                            HStack(spacing: 10) {
                                PokemonIcons(names: decks.icons(for: row.deck, archetypes: archetypes), size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.deck.name).fontWeight(.medium).lineLimit(1)
                                    Text("Modificado \(row.deck.modified.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let archetype = row.archetype {
                                Badge(text: archetype.name, color: archetype.color.color)
                            } else {
                                Text("—").foregroundStyle(.tertiary)
                            }
                            Text("\(row.stats.total)").monospacedDigit()
                            Text(row.stats.total > 0 ? row.stats.record : "—").monospacedDigit()
                            WinRateBar(rate: row.stats.winRate)
                            StatusBadge(status: row.deck.currentStatus)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .onTapGesture { actions.select(.deck(row.deck.id)) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    /// Eventos que ya terminaron (o con posición anotada) dentro del periodo elegido, del más reciente al más viejo.
    private var finishedEvents: [TournamentEvent] {
        events.items
            .filter { !$0.isUpcoming() || $0.finish != nil }
            .filter { scope == .all || AgeDivision.season(on: $0.startDate) == season }
            .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var eventResultsPanel: some View {
        let finished = finishedEvents
        if !events.items.isEmpty {
            Panel(title: "Resultados en eventos", subtitle: "Tu posición y récord en los eventos más recientes") {
                Button("Ver todos") { actions.select(.events) }
                    .buttonStyle(.link)
            } content: {
                if finished.isEmpty {
                    emptyState("Todavía no terminas ningún evento en este periodo.", button: nil, action: nil)
                } else {
                    EventResultsTable(events: Array(finished.prefix(6))) { actions.select(.event($0.id)) }
                }
            }
        }
    }

    private var recentPanel: some View {
        let recent = scopedMatches.sorted { $0.date > $1.date }.prefix(6)
        return Panel(title: "Actividad reciente") {
            Button("Historial completo") { actions.select(.matches) }
                .buttonStyle(.link)
        } content: {
            if recent.isEmpty {
                emptyState("Todavía no registras partidas en este periodo.", button: "Registrar partida") { actions.logMatch(nil) }
            } else {
                MatchList(matches: Array(recent), onSelect: { actions.showMatch($0.id) })
            }
        }
    }

    // MARK: - Columna lateral

    private func sideColumn(_ analytics: Analytics) -> some View {
        VStack(spacing: 20) {
            usagePanel(analytics)
            bestDeckPanel(analytics)
            bestResultsPanel(.cup, title: "Mejores resultados en Cups")
            bestResultsPanel(.challenge, title: "Mejores resultados en Challenges")
            eventsPanel
        }
    }

    private func usagePanel(_ analytics: Analytics) -> some View {
        let played = analytics.archetypePerformance.filter { $0.stats.total > 0 }
        let total = Double(played.reduce(0) { $0 + $1.stats.total })
        let top = played.prefix(4)
        let others = played.dropFirst(4).reduce(0) { $0 + $1.stats.total }
        let slices = top.map { PieSlice(label: $0.name, value: Double($0.stats.total), color: $0.archetype?.color.color ?? .gray,
                                          icons: $0.archetype?.iconNames ?? []) }
            + (others > 0 ? [PieSlice(label: "Otros", value: Double(others), color: .gray.opacity(0.5))] : [])
        return Panel(title: "Uso por arquetipo", subtitle: "Qué porcentaje de tus partidas juegas con cada uno") {
            if slices.isEmpty {
                emptyState("Registra partidas para ver la gráfica.", button: nil, action: nil)
            } else {
                VStack(spacing: 14) {
                    PieChart(slices: slices)
                        .frame(height: 220)
                    VStack(spacing: 8) {
                        ForEach(slices) { slice in
                            LegendRow(color: slice.color, label: slice.label, value: percentText(slice.value / total), icons: slice.icons)
                        }
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
        }
    }

    private func bestDeckPanel(_ analytics: Analytics) -> some View {
        Panel(title: "El mazo que mejor me va", subtitle: "Mejor win rate (con al menos 3 partidas)") {
            if let best = analytics.bestDeck {
                let stats = best.stats
                VStack(spacing: 14) {
                    PieChart(slices: [
                        PieSlice(label: "Victorias", value: Double(stats.wins), color: .green),
                        PieSlice(label: "Derrotas", value: Double(stats.losses), color: .red),
                        PieSlice(label: "Empates", value: Double(stats.ties), color: .gray),
                    ].filter { $0.value > 0 }, title: percentText(stats.winRate), subtitle: stats.record)
                        .frame(height: 200)
                    HStack(spacing: 10) {
                        PokemonIcons(names: decks.icons(for: best.deck, archetypes: archetypes), size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(best.deck.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(best.archetype?.name ?? "Sin arquetipo") · \(stats.total) partidas")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { actions.select(.deck(best.deck.id)) }
                    VStack(spacing: 6) {
                        LegendRow(color: .green, label: "Victorias", value: "\(stats.wins)")
                        LegendRow(color: .red, label: "Derrotas", value: "\(stats.losses)")
                        if stats.ties > 0 { LegendRow(color: .gray, label: "Empates", value: "\(stats.ties)") }
                    }
                }
                .padding([.horizontal, .bottom], 16)
            } else {
                emptyState("Registra partidas para saber qué mazo te funciona mejor.", button: nil, action: nil)
            }
        }
    }

    /// Los 5 mejores resultados en un tipo de evento (con posición anotada) dentro del periodo elegido.
    private func bestResultsPanel(_ kind: EventKind, title: String) -> some View {
        let best = events.items
            .filter { $0.kind == kind && $0.finish != nil }
            .filter { scope == .all || AgeDivision.season(on: $0.startDate) == season }
            .sorted { a, b in
                guard let x = a.finish, let y = b.finish else { return false }
                if x != y { return Placement.isBetter(x, than: y) }
                return a.startDate > b.startDate
            }
            .prefix(5)
        return Panel(title: title) {
            if best.isEmpty {
                Text("Anota tu posición final en tus \(kind.title)s para verlas aquí.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(best.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider() }
                        BestResultRow(event: event)
                            .onTapGesture { actions.select(.event(event.id)) }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var eventsPanel: some View {
        Panel(title: "Próximos eventos") {
            Button("Ver todos") { actions.select(.events) }
                .buttonStyle(.link)
        } content: {
            if upcomingEvents.isEmpty {
                emptyState("Agrega los torneos a los que piensas ir.", button: "Nuevo evento") { actions.editEvent(nil) }
            } else {
                VStack(spacing: 10) {
                    ForEach(upcomingEvents.prefix(3)) { event in
                        EventSummary(event: event, deckName: event.plannedDeckID.flatMap(decks.deck)?.name)
                            .contentShape(Rectangle())
                            .onTapGesture { actions.select(.event(event.id)) }
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
        }
    }

    private func emptyState(_ text: String, button: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let button, let action {
                Button(button, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}

/// Evento en una tarjeta compacta (dashboard y lista de eventos).
/// Tabla de resultados de eventos: posición, evento, fecha, mazo, récord y win rate.
struct EventResultsTable: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    let events: [TournamentEvent]
    let onSelect: (TournamentEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Posición").frame(width: 92, alignment: .leading)
                Text("Evento").frame(maxWidth: .infinity, alignment: .leading)
                Text("Fecha").frame(width: 92, alignment: .leading)
                Text("Mazo").frame(maxWidth: .infinity, alignment: .leading)
                Text("V - D - E").frame(width: 64, alignment: .trailing)
                Text("Win rate").frame(width: 108, alignment: .leading)
                Color.clear.frame(width: 10, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ForEach(events) { event in
                Divider()
                let eventMatches = matches.items.filter { $0.eventID == event.id }
                let deck = event.playedDeckID(in: eventMatches).flatMap(decks.deck)
                EventResultRow(event: event, stats: eventMatches.stats, deckName: deck?.name,
                               deckIcons: deck.map { decks.icons(for: $0, archetypes: archetypes) } ?? [])
                    .onTapGesture { onSelect(event) }
            }
        }
        .padding(.bottom, 4)
    }
}

/// Fila compacta para las tablas de mejores resultados de la columna lateral.
private struct BestResultRow: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    let event: TournamentEvent
    @State private var hovering = false

    var body: some View {
        let finish = event.finish
        let deck = event.playedDeckID(in: matches.items.filter { $0.eventID == event.id }).flatMap(decks.deck)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: finish?.symbol ?? "flag.checkered").font(.caption)
                    Text(finish?.ordinal ?? "—").monospacedDigit()
                }
                .font(.callout.weight(.bold))
                .foregroundStyle(finish?.color ?? .secondary)
                if let title = finish?.title {
                    Text(title).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name.isEmpty ? "Evento sin nombre" : event.name)
                    .font(.callout.weight(.medium))
                Text([event.startDate.formatted(.dateTime.day().month(.abbreviated).year()),
                      finish?.players.map { "\($0) jugadores" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let deck {
                PokemonIcons(names: decks.icons(for: deck, archetypes: archetypes), size: 24)
                    .help(deck.name)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Abrir la página del evento")
    }
}

private struct EventResultRow: View {
    let event: TournamentEvent
    let stats: MatchStats
    let deckName: String?
    let deckIcons: [String]
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            placement.frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name.isEmpty ? "Evento sin nombre" : event.name).fontWeight(.medium)
                Text(event.kind.title).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(event.startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.callout)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: 8) {
                if let deckName {
                    PokemonIcons(names: deckIcons, size: 26)
                    Text(deckName).lineLimit(1)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(stats.total > 0 ? "\(stats.wins)-\(stats.losses)-\(stats.ties)" : "—")
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            WinRateBar(rate: stats.winRate)
                .frame(width: 108, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Abrir la página del evento")
    }

    /// «🥇 1.º / 64» con el color de la medalla, o un guion si no la anotaste.
    @ViewBuilder
    private var placement: some View {
        if let finish = event.finish {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: finish.symbol)
                    Text(finish.ordinal).monospacedDigit()
                    if let players = finish.players {
                        Text("/ \(players)").foregroundStyle(.secondary).fontWeight(.regular).monospacedDigit()
                    }
                }
                .font(.callout.weight(.bold))
                .foregroundStyle(finish.color)
                if let title = finish.title {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Sin anotar").font(.callout).foregroundStyle(.tertiary)
        }
    }
}

struct EventSummary: View {
    let event: TournamentEvent
    let deckName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name.isEmpty ? "Evento sin nombre" : event.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(event.kind.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if event.registered {
                    Badge(text: "INSCRITO", color: .green)
                } else if let url = event.url {
                    Link(destination: url) {
                        Text("ABRIR").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Group {
                Label(dateText, systemImage: "clock")
                if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
                HStack(spacing: 12) {
                    if let cost = event.costText { Label(cost, systemImage: "dollarsign.circle") }
                    if let deckName { Label(deckName, systemImage: "rectangle.stack") }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.7)))
    }

    private var dateText: String {
        let start = event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        guard let end = event.endDate, !Calendar.current.isDate(end, inSameDayAs: event.startDate) else { return start }
        return "\(start) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }
}
