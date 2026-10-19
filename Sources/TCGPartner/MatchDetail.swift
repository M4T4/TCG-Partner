import AppKit
import DeckKit
import SwiftUI

/// Lista de partidas con columnas; cada fila abre la ficha completa de la partida.
struct MatchList: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var events: EventStore
    let matches: [MatchRecord]
    /// Columna de ronda (página de un evento).
    var showRound = false
    /// Columna de evento (no hace falta dentro de la página de un evento).
    var showEvent = true
    /// Pinta la fila de verde si ganaste y de rojo si perdiste.
    var tintByResult = false
    let onSelect: (MatchRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showRound { Text("Ronda").frame(width: 70, alignment: .leading) }
                Text("Resultado").frame(width: 92, alignment: .leading)
                Text("Fecha").frame(width: 112, alignment: .leading)
                Text("Tipo").frame(width: 92, alignment: .leading)
                Text("Mi mazo").frame(maxWidth: .infinity, alignment: .leading)
                Text("Rival").frame(maxWidth: .infinity, alignment: .leading)
                if showEvent { Text("Evento").frame(maxWidth: 150, alignment: .leading) }
                Color.clear.frame(width: 10, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ForEach(matches) { match in
                Divider()
                let deck = match.deckID.flatMap(decks.deck)
                MatchListRow(match: match,
                             deckName: deck?.name,
                             deckIcons: deck.map { decks.icons(for: $0, archetypes: archetypes) } ?? [],
                             eventName: events.item(match.eventID)?.name,
                             showRound: showRound, showEvent: showEvent, tintByResult: tintByResult)
                    .onTapGesture { onSelect(match) }
            }
        }
        .padding(.bottom, 6)
    }
}

private struct MatchListRow: View {
    let match: MatchRecord
    let deckName: String?
    let deckIcons: [String]
    let eventName: String?
    let showRound: Bool
    let showEvent: Bool
    let tintByResult: Bool
    @State private var hovering = false

    /// Verde si gané, rojo si perdí; los empates quedan sin color.
    private var rowTint: Color {
        guard tintByResult, match.result != .tie else { return .clear }
        return match.result.color.opacity(0.13)
    }

    var body: some View {
        HStack(spacing: 12) {
            if showRound {
                Text(match.round?.isEmpty == false ? match.round! : "—")
                    .fontWeight(.semibold)
                    .foregroundStyle(match.round?.isEmpty == false ? .primary : .tertiary)
                    .frame(width: 70, alignment: .leading)
            }
            Label(match.result.title, systemImage: match.result.symbol)
                .foregroundStyle(match.result.color)
                .fontWeight(.semibold)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(match.date.formatted(.relative(presentation: .named)))
                Text(match.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)
            Label(match.currentKind.title, systemImage: match.currentKind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: 6) {
                if !deckIcons.isEmpty { PokemonIcons(names: deckIcons, size: 22) }
                Text(deckName ?? "—")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if !match.opponentArchetype.isEmpty {
                    PokemonIcons(names: PokemonIcon.split(match.opponentArchetype), size: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.opponent.isEmpty ? "—" : match.opponent)
                    if !match.opponentArchetype.isEmpty {
                        Text(match.opponentArchetype).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showEvent {
                Text(eventName ?? "—")
                    .foregroundStyle(eventName == nil ? .tertiary : .secondary)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 10)
        }
        .lineLimit(1)
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(rowTint)
        .overlay(alignment: .leading) {
            if tintByResult, match.result != .tie {
                Rectangle().fill(match.result.color).frame(width: 3)
            }
        }
        .overlay {
            // Resalte al pasar el ratón, encima del color del resultado.
            if hovering { Color.primary.opacity(0.06).allowsHitTesting(false) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Ver toda la información de la partida")
    }
}

/// Ficha de una partida con todo lo relacionado: mazos, rival, evento, datos del battle log y el log completo.
struct MatchDetailView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    let matchID: UUID
    let actions: AppActions
    let onEdit: (MatchRecord) -> Void

    @State private var confirmDelete = false
    @State private var copied = false

    var body: some View {
        if let match = matches.item(matchID) {
            content(match)
        } else {
            ContentUnavailableView("La partida ya no existe", systemImage: "questionmark.circle")
                .frame(width: 560, height: 300)
        }
    }

    private func content(_ match: MatchRecord) -> some View {
        let deck = match.deckID.flatMap(decks.deck)
        let archetype = deck.flatMap { archetypes.item(decks.archetypeID(of: $0)) }
        let event = events.item(match.eventID)
        let log = match.battleLog.flatMap(BattleLogParser.parse)
        let me = log.flatMap { $0.players.first { $0.caseInsensitiveCompare(match.opponent) != .orderedSame } }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(match, log: log)

                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        detailRow("Fecha", match.date.formatted(date: .complete, time: .shortened))
                        detailRow("Tipo", match.currentKind.title, symbol: match.currentKind.symbol)
                        if let wentFirst = match.wentFirst {
                            detailRow("Turno inicial", wentFirst ? "Empecé yo" : "Empezó el rival")
                        }
                        if let turns = match.turns { detailRow("Turnos", "\(turns)") }
                        if let mine = match.myPrizes, let theirs = match.opponentPrizes {
                            detailRow("Premios tomados", "\(mine) yo · \(theirs) rival")
                        }
                        if let round = match.round, !round.isEmpty { detailRow("Ronda o mesa", round) }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        sideCard("Mi mazo") {
                            if let deck {
                                HStack(spacing: 10) {
                                    PokemonIcons(names: decks.icons(for: deck, archetypes: archetypes), size: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(deck.name).fontWeight(.semibold)
                                        if let archetype { Badge(text: archetype.name, color: archetype.color.color) }
                                        if let me { Text("Como \(me)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                Button("Abrir mazo") { open(.deck(deck.id)) }
                                    .buttonStyle(.link)
                            } else {
                                Text("Sin mazo").foregroundStyle(.secondary)
                            }
                        }
                        sideCard("Rival") {
                            if !match.opponentArchetype.isEmpty {
                                PokemonIcons(names: PokemonIcon.split(match.opponentArchetype), size: 40)
                            }
                            Text(match.opponent.isEmpty ? "Sin nombre" : match.opponent).fontWeight(.semibold)
                            Text(match.opponentArchetype.isEmpty ? "Mazo sin indicar" : match.opponentArchetype)
                                .foregroundStyle(.secondary)
                            if let log, let rival = log.opponent(of: me ?? ""), let pokemon = log.pokemon[rival], !pokemon.isEmpty {
                                Text("Jugó: " + pokemon.prefix(8).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if let event {
                        sideCard("Evento") {
                            EventSummary(event: event, deckName: event.plannedDeckID.flatMap(decks.deck)?.name)
                            let record = matches.items.filter { $0.eventID == event.id }.stats
                            Text("Tu récord en este evento: \(record.record) · \(percentText(record.winRate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if deck != nil {
                        headToHead(match)
                    }

                    if !match.notes.isEmpty {
                        sideCard("Notas") {
                            Text(match.notes).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let battleLog = match.battleLog {
                        battleLogCard(battleLog)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Eliminar", role: .destructive) { confirmDelete = true }
                Spacer()
                if let archetype {
                    journalButton(match, archetype: archetype)
                }
                Button("Editar…") { onEdit(match) }
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 600, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("¿Eliminar esta partida?", isPresented: $confirmDelete) {
            Button("Eliminar partida", role: .destructive) {
                matches.delete(match.id)
                dismiss()
            }
        }
    }

    /// Abre el aprendizaje de esta partida en el journal del arquetipo (o crea uno nuevo, ya ligado).
    private func journalButton(_ match: MatchRecord, archetype: Archetype) -> some View {
        let existing = journal.items.first { $0.matchID == match.id }
        return Button {
            let id: UUID
            if let existing {
                id = existing.id
            } else {
                let rival = match.opponentArchetype.isEmpty ? match.opponent : match.opponentArchetype
                let entry = JournalEntry(archetypeID: archetype.id, kind: .lesson,
                                         title: rival.isEmpty ? "" : "\(match.result.title) contra \(rival)",
                                         opponent: match.opponentArchetype, matchID: match.id)
                journal.save(entry)
                id = entry.id
            }
            dismiss()
            actions.select(.journal(archetype.id, entry: id))
        } label: {
            Label(existing == nil ? "Anotar aprendizaje" : "Ver en el journal", systemImage: "lightbulb")
        }
        .help("Escribe en el journal de \(archetype.name) lo que aprendiste en esta partida")
    }

    private func header(_ match: MatchRecord, log: BattleLogSummary?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: match.result.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(match.result.color)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(match.result.color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(match.headline).font(.title2.bold()).lineLimit(2)
                if let log, let winner = log.winner, let reason = log.endReason {
                    Text("\(winner) gana · \(reason.title)").foregroundStyle(.secondary)
                } else {
                    Text(match.date.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Récord contra el mismo mazo rival (y contra el mismo jugador), para ver el contexto de la partida.
    @ViewBuilder
    private func headToHead(_ match: MatchRecord) -> some View {
        let sameDeck = match.opponentArchetype.isEmpty ? [] : matches.items.filter {
            $0.opponentArchetype.caseInsensitiveCompare(match.opponentArchetype) == .orderedSame
        }
        let samePlayer = match.opponent.isEmpty ? [] : matches.items.filter {
            $0.opponent.caseInsensitiveCompare(match.opponent) == .orderedSame
        }
        if sameDeck.count > 1 || samePlayer.count > 1 {
            sideCard("Historial relacionado") {
                if sameDeck.count > 1 {
                    let stats = sameDeck.stats
                    Text("Contra \(match.opponentArchetype): \(stats.record) · \(percentText(stats.winRate))")
                        .foregroundStyle(winRateColor(stats.winRate))
                }
                if samePlayer.count > 1 {
                    let stats = samePlayer.stats
                    Text("Contra \(match.opponent): \(stats.record) en \(stats.total) partidas")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func battleLogCard(_ battleLog: String) -> some View {
        sideCard("Battle log") {
            ScrollView {
                Text(battleLog)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            Button(copied ? "Copiado" : "Copiar battle log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(battleLog, forType: .string)
                copied = true
            }
            .buttonStyle(.link)
        }
    }

    private func detailRow(_ label: String, _ value: String, symbol: String? = nil) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            if let symbol {
                Label(value, systemImage: symbol)
            } else {
                Text(value)
            }
        }
    }

    private func sideCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6)))
    }

    private func open(_ item: SidebarItem) {
        dismiss()
        actions.select(item)
    }
}
