import DeckKit
import SwiftUI

/// Página de un evento: sus datos, tu récord y las partidas por ronda.
struct EventPage: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    let event: TournamentEvent
    let actions: AppActions
    @CompactWidth private var compact

    /// Partidas del evento, por ronda (las que no tienen ronda, al final por fecha).
    private var eventMatches: [MatchRecord] {
        matches.items.filter { $0.eventID == event.id }.sorted { a, b in
            switch (a.roundNumber, b.roundNumber) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.date < b.date
            }
        }
    }

    /// El mazo que más usaste en el evento o, si no hay partidas, el que planeabas jugar.
    private var playedDeck: Deck? {
        event.playedDeckID(in: eventMatches).flatMap(decks.deck)
    }

    var body: some View {
        let stats = eventMatches.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if compact { compactHeader } else { header }
                statCards(stats)
                Panel(title: "Partidas por ronda",
                      subtitle: eventMatches.isEmpty ? nil : "Verde si ganaste, rojo si perdiste. \(compact ? "Toca" : "Haz clic") para ver todos los datos") {
                    registerMenu(compact: true)
                } content: {
                    if eventMatches.isEmpty {
                        VStack(spacing: 10) {
                            Text("Todavía no registras partidas en este evento.")
                                .foregroundStyle(.secondary)
                            registerMenu(compact: false)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                    } else {
                        MatchList(matches: eventMatches, showRound: true, showEvent: false, tintByResult: true) {
                            actions.showMatch($0.id)
                        }
                    }
                }
                if !event.notes.isEmpty {
                    Panel(title: "Notas") {
                        Text(event.notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .bottom], 16)
                    }
                }
            }
            .padding(compact ? 16 : 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle(event.name)
        .toolbar {
            if compact {
                // En iPhone ya hay botón para volver; aquí van Editar y el enlace.
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { actions.editEvent(event) }
                }
                if let url = event.url {
                    ToolbarItem(placement: .secondaryAction) {
                        Link(destination: url) { Label("Abrir enlace", systemImage: "arrow.up.right.square") }
                    }
                }
            } else {
                ToolbarItem(placement: .navigation) {
                    Button { actions.select(.events) } label: {
                        Label("Eventos", systemImage: "chevron.left")
                    }
                    .help("Volver a todos los eventos")
                }
            }
        }
    }

    /// iPhone: etiquetas, datos uno debajo de otro y el botón de registrar a lo ancho.
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { badges }
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(dateText, systemImage: "calendar")
                if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
                if let cost = event.costText { Label(cost, systemImage: "dollarsign.circle") }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            registerMenu(compact: false, fullWidth: true)
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var badges: some View {
        Badge(text: event.kind.title, color: .accentColor)
        Badge(text: event.format.title, color: .secondary)
        if event.registered { Badge(text: "INSCRITO", color: .green) }
        if !event.isUpcoming() { Badge(text: "TERMINADO", color: .secondary) }
        if let finish = event.finish { PlacementBadge(placement: finish) }
    }

    // MARK: - Partes

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { badges }
                Text(event.name.isEmpty ? "Evento sin nombre" : event.name)
                    .font(.largeTitle.bold())
                HStack(spacing: 14) {
                    Label(dateText, systemImage: "calendar")
                    if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
                    if let cost = event.costText { Label(cost, systemImage: "dollarsign.circle") }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = event.url {
                Link(destination: url) {
                    Label("Abrir enlace", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
            Button("Editar…") { actions.editEvent(event) }
            registerMenu(compact: false)
                .buttonStyle(.borderedProminent)
        }
    }

    private func statCards(_ stats: MatchStats) -> some View {
        // La tarjeta de posición aparece cuando ya la anotaste o cuando el evento terminó.
        let showsPlacement = event.finish != nil || !event.isUpcoming()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: compact ? 2 : (showsPlacement ? 5 : 4)), spacing: compact ? 10 : 14) {
            if showsPlacement {
                placementCard
            }
            StatCard(title: "Récord", value: stats.total > 0 ? stats.record : "—",
                     detail: stats.total == 1 ? "1 partida" : "\(stats.total) partidas", symbol: "trophy")
            StatCard(title: "Win rate", value: percentText(stats.winRate), valueColor: winRateColor(stats.winRate),
                     detail: stats.total > 0 ? "\(plural(stats.wins, "victoria", "victorias")) · \(plural(stats.losses, "derrota", "derrotas"))" : "Sin partidas",
                     symbol: "chart.line.uptrend.xyaxis")
            StatCard(title: "Rondas jugadas", value: "\(Set(eventMatches.compactMap(\.roundNumber)).count)",
                     detail: eventMatches.compactMap(\.roundNumber).max().map { "Hasta la ronda \($0)" } ?? "Sin rondas anotadas",
                     symbol: "list.number")
            StatCard(title: eventMatches.isEmpty ? "Mazo planeado" : "Mazo jugado", value: playedDeck?.name ?? "—",
                     detail: playedDeck.flatMap { archetypes.item(decks.archetypeID(of: $0))?.name } ?? "Sin arquetipo",
                     symbol: "rectangle.stack")
        }
    }

    private var placementCard: some View {
        let finish = event.finish
        return StatCard(title: "Posición final", value: finish?.ordinal ?? "—", valueColor: finish?.color ?? .primary,
                        detail: finish.map { f in
                            [f.players.map { "de \($0) jugadores" }, f.title].compactMap { $0 }.joined(separator: " · ")
                        } ?? "Anótala con Editar…",
                        symbol: finish?.symbol ?? "flag.checkered")
            .contentShape(Rectangle())
            .onTapGesture { actions.editEvent(event) }
            .help("Editar la posición final")
    }

    private func registerMenu(compact: Bool, fullWidth: Bool = false) -> some View {
        Menu {
            Button { log(.inPerson) } label: {
                Label("Partida presencial…", systemImage: MatchKind.inPerson.symbol)
            }
            Button { log(.online) } label: {
                Label("Partida en PTCG Live…", systemImage: MatchKind.online.symbol)
            }
        } label: {
            Label(compact ? "Partida" : "Registrar partida", systemImage: "plus")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .fixedSize(horizontal: !fullWidth, vertical: true)
    }

    private func log(_ kind: MatchKind) {
        let next = (eventMatches.compactMap(\.roundNumber).max() ?? 0) + 1
        var match = MatchRecord(deckID: playedDeck?.id, eventID: event.id, kind: kind)
        match.round = "Ronda \(next)"
        // Si el evento ya pasó, la partida se fecha el día del evento.
        if !event.isUpcoming() { match.date = event.startDate }
        actions.newMatch(match)
    }

    private func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    private var dateText: String {
        let start = event.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        guard let end = event.endDate, !Calendar.current.isDate(end, inSameDayAs: event.startDate) else { return start }
        return "\(start) – \(end.formatted(.dateTime.day().month(.wide)))"
    }
}
