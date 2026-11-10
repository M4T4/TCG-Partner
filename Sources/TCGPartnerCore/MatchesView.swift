import DeckKit
import SwiftUI

/// Historial de partidas con filtros y resumen.
struct MatchesView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    let actions: AppActions
    var onEdit: (MatchRecord) -> Void

    @State private var deckFilter: UUID?
    @State private var resultFilter: MatchResult?
    @State private var kindFilter: MatchKind?
    @State private var selection = Set<MatchRecord.ID>()
    @State private var sortOrder = [KeyPathComparator(\HistoryRow.date, order: .reverse)]
    @CompactWidth private var compact

    /// Fila ya resuelta para la tabla (nombres en lugar de ids, para poder ordenar).
    struct HistoryRow: Identifiable {
        let match: MatchRecord
        let deck: String
        let deckIcons: [String]
        let archetype: String
        let event: String
        var id: UUID { match.id }
        var date: Date { match.date }
        var result: String { match.result.title }
        var kind: String { match.currentKind.title }
        var opponent: String { match.opponent }
        var opponentArchetype: String { match.opponentArchetype }
    }

    private var filtered: [MatchRecord] {
        matches.items.filter {
            (deckFilter == nil || $0.deckID == deckFilter) && (resultFilter == nil || $0.result == resultFilter)
                && (kindFilter == nil || $0.currentKind == kindFilter)
        }
    }

    private var rows: [HistoryRow] {
        filtered.map { match in
            let deck = match.deckID.flatMap(decks.deck)
            return HistoryRow(match: match, deck: deck?.name ?? "—",
                              deckIcons: deck.map { decks.icons(for: $0, archetypes: archetypes) } ?? [],
                            archetype: deck.flatMap { archetypes.item(decks.archetypeID(of: $0))?.name } ?? "—",
                            event: events.item(match.eventID)?.name ?? "")
        }
        .sorted(using: sortOrder)
    }

    private var summaryText: String {
        let stats = filtered.stats
        return stats.total == 0 ? "Sin partidas" : "\(stats.total) partidas · récord \(stats.record) · \(percentText(stats.winRate))"
    }

    private var hasFilters: Bool {
        deckFilter != nil || resultFilter != nil || kindFilter != nil
    }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .overlay {
            if matches.items.isEmpty {
                ContentUnavailableView {
                    Label("Sin partidas", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Registra tus partidas para ver win rates y gráficas en el dashboard.")
                } actions: {
                    Button("Registrar partida") { actions.logMatch(nil) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { actions.logMatch(deckFilter) } label: {
                    Label("Registrar partida", systemImage: "plus")
                }
                .help("Registrar partida (⌘R)")
            }
        }
    }

    // MARK: - iPhone

    /// Lista de partidas, de la más reciente a la más vieja; los filtros van en un menú.
    private var compactBody: some View {
        List {
            if !matches.items.isEmpty {
                Section {
                    Picker("Resultado", selection: $resultFilter) {
                        Text("Todos").tag(MatchResult?.none)
                        ForEach(MatchResult.allCases) { Text($0.title).tag(MatchResult?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(summaryText)
                }
            }
            Section {
                ForEach(rows) { row in
                    MatchListRow(match: row.match, deckName: row.deck == "—" ? nil : row.deck, deckIcons: row.deckIcons,
                                 eventName: row.event.isEmpty ? nil : row.event,
                                 showRound: false, showEvent: false, tintByResult: false, compact: true)
                        .listRowInsets(EdgeInsets())
                        .onTapGesture { actions.showMatch(row.id) }
                        .swipeActions(edge: .trailing) {
                            Button("Eliminar", systemImage: "trash", role: .destructive) { matches.delete(row.id) }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Editar", systemImage: "pencil") { onEdit(row.match) }
                                .tint(.accentColor)
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) { filterMenu }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Mazo", selection: $deckFilter) {
                Text("Todos los mazos").tag(UUID?.none)
                ForEach(decks.decks.sorted { $0.name < $1.name }) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            Picker("Tipo", selection: $kindFilter) {
                Text("Todas").tag(MatchKind?.none)
                ForEach(MatchKind.allCases) { Label($0.title, systemImage: $0.symbol).tag(MatchKind?.some($0)) }
            }
            .pickerStyle(.menu)
            if hasFilters {
                Button("Quitar filtros", systemImage: "xmark.circle", role: .destructive) {
                    deckFilter = nil
                    kindFilter = nil
                    resultFilter = nil
                }
            }
        } label: {
            Label("Filtros", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Mac

    private var fullBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Partidas").font(.title.bold())
                    Text(summaryText)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mazo", selection: $deckFilter) {
                    Text("Todos los mazos").tag(UUID?.none)
                    Divider()
                    ForEach(decks.decks.sorted { $0.name < $1.name }) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .fixedSize()
                Picker("Tipo", selection: $kindFilter) {
                    Text("Todas").tag(MatchKind?.none)
                    ForEach(MatchKind.allCases) { Text($0.title).tag(MatchKind?.some($0)) }
                }
                .fixedSize()
                Picker("Resultado", selection: $resultFilter) {
                    Text("Todos").tag(MatchResult?.none)
                    ForEach(MatchResult.allCases) { Text($0.title).tag(MatchResult?.some($0)) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(20)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Fecha", value: \.date) { row in
                    Text(row.date.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 130, ideal: 150)
                TableColumn("Resultado", value: \.result) { row in
                    Label(row.match.result.title, systemImage: row.match.result.symbol)
                        .foregroundStyle(row.match.result.color)
                }
                .width(min: 90, ideal: 100)
                TableColumn("Tipo", value: \.kind) { row in
                    Label(row.kind, systemImage: row.match.currentKind.symbol)
                        .foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 105)
                TableColumn("Mazo", value: \.deck) { row in
                    HStack(spacing: 6) {
                        if !row.deckIcons.isEmpty { PokemonIcons(names: row.deckIcons, size: 22) }
                        Text(row.deck)
                    }
                }
                TableColumn("Arquetipo", value: \.archetype)
                TableColumn("Rival", value: \.opponent)
                TableColumn("Mazo rival", value: \.opponentArchetype) { row in
                    HStack(spacing: 6) {
                        if !row.opponentArchetype.isEmpty {
                            PokemonIcons(names: PokemonIcon.split(row.opponentArchetype), size: 22)
                        }
                        Text(row.opponentArchetype)
                    }
                }
                TableColumn("Evento", value: \.event)
            }
            .contextMenu(forSelectionType: MatchRecord.ID.self) { ids in
                if ids.count == 1, let match = matches.item(ids.first) {
                    Button("Ver detalles…") { actions.showMatch(match.id) }
                    Button("Editar…") { onEdit(match) }
                }
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Eliminar partida" : "Eliminar \(ids.count) partidas", role: .destructive) {
                        ids.forEach(matches.delete)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { actions.showMatch(id) }
            }
            .onDeleteKey {
                selection.forEach(matches.delete)
                selection = []
            }
        }
    }
}

/// Formulario para registrar o editar una partida: en PTCG Live (con battle log) o presencial.
struct MatchEditor: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss

    @State var match: MatchRecord
    let isNew: Bool

    /// Tus nombres de usuario de PTCG Live (uno por línea), para saber cuál eres en el log.
    @AppStorage("ptcgl.usernames") private var savedUsernames = ""
    @AppStorage("match.lastKind") private var lastKind = MatchKind.online
    @State private var log = ""
    @State private var me: String?
    /// Arquetipo del mazo con el que se abrió el formulario: sus mazos salen primero.
    @State private var contextArchetype: UUID?

    private var knownNames: [String] {
        savedUsernames.split(separator: "\n").map(String.init)
    }

    private var summary: BattleLogSummary? { BattleLogParser.parse(log) }

    private var kind: Binding<MatchKind> {
        Binding(get: { match.currentKind }, set: { match.kind = $0 })
    }

    /// Mazos de rival ya usados y arquetipos propios, para sugerir.
    private var typedSuggestions: [String] {
        let names = Set(matches.items.map(\.opponentArchetype) + archetypes.items.map(\.name))
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(match.opponentArchetype) && $0 != match.opponentArchetype }
        return names.sorted().prefix(6).map { $0 }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(isNew ? "Registrar partida" : "Editar partida")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isNew ? "Registrar" : "Guardar", action: save)
                    }
                }
        }
        .onAppear(perform: setUp)
        .onChange(of: log) { detectMe() }
        .onChange(of: me) { applyLog() }
        #else
        VStack(spacing: 0) {
            form
            HStack {
                if !isNew {
                    Button("Eliminar", role: .destructive) {
                        matches.delete(match.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Registrar" : "Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .sheetFrame(width: 520, height: match.currentKind == .online ? 760 : 620)
        .onAppear(perform: setUp)
        .onChange(of: log) { detectMe() }
        .onChange(of: me) { applyLog() }
        #endif
    }

    private var form: some View {
            Form {
                Section {
                    Picker("Tipo de partida", selection: kind) {
                        Label("PTCG Live", systemImage: "globe").tag(MatchKind.online)
                        Label("Presencial", systemImage: "person.2").tag(MatchKind.inPerson)
                    }
                    .pickerStyle(.segmented)
                }
                if match.currentKind == .online { battleLogSection }
                Section("Partida") {
                    Picker("Resultado", selection: $match.result) {
                        ForEach(MatchResult.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Fecha", selection: $match.date)
                    deckPicker
                    Picker("¿Empezaste tú?", selection: $match.wentFirst) {
                        Text("—").tag(Bool?.none)
                        Text("Sí").tag(Bool?.some(true))
                        Text("No").tag(Bool?.some(false))
                    }
                    .labeledSegmentedPickerStyle()
                }
                Section("Rival") {
                    TextField("Jugador", text: $match.opponent,
                              prompt: Text(match.currentKind == .online ? "Se llena con el battle log" : "Nombre del rival"))
                        .formLabel("Jugador")
                    TextField("Mazo del rival", text: $match.opponentArchetype, prompt: Text("Ej. Gardevoir ex"))
                        .formLabel("Mazo")
                    suggestionChips
                }
                Section {
                    Picker("Evento", selection: $match.eventID) {
                        Text("Ninguno").tag(UUID?.none)
                        Divider()
                        ForEach(events.items.sorted { $0.startDate > $1.startDate }) { event in
                            Text(event.name.isEmpty ? "Evento sin nombre" : event.name).tag(UUID?.some(event.id))
                        }
                    }
                    if match.currentKind == .inPerson || match.eventID != nil {
                        TextField("Ronda o mesa", text: Binding(get: { match.round ?? "" },
                                                                set: { match.round = $0.isEmpty ? nil : $0 }),
                                  prompt: Text("Ej. Ronda 3 · Mesa 12"))
                            .formLabel("Ronda o mesa")
                    }
                    TextField("Notas", text: $match.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                #if os(iOS)
                if !isNew {
                    Section {
                        Button("Eliminar partida", role: .destructive) {
                            matches.delete(match.id)
                            dismiss()
                        }
                    }
                }
                #endif
            }
            .formStyle(.grouped)
    }

    // MARK: - Battle log

    private var battleLogSection: some View {
        Section {
            TextEditor(text: $log)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .overlay(alignment: .topLeading) {
                    if log.isEmpty {
                        Text("En PTCG Live: resumen de la partida › Battle Log › copiar, y pégalo aquí.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Button("Pegar del portapapeles") {
                    log = Clipboard.string ?? log
                }
                Spacer()
                if !log.isEmpty {
                    Button("Borrar", role: .destructive) { log = "" }
                        .buttonStyle(.borderless)
                }
            }
            detection
        } header: {
            Text("Battle log")
        }
    }

    @ViewBuilder
    private var detection: some View {
        if !log.isEmpty, summary == nil {
            Label("No parece un battle log de PTCG Live: no encontré a los dos jugadores.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let summary {
            Picker("¿Cuál eres tú?", selection: $me) {
                ForEach(summary.players, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .pickerStyle(.segmented)
            if let me {
                VStack(alignment: .leading, spacing: 4) {
                    if let result = summary.result(for: me) {
                        Label(resultLine(result, summary), systemImage: result.symbol)
                            .foregroundStyle(result.color)
                            .fontWeight(.semibold)
                    } else {
                        Label("El log no dice quién ganó: elige el resultado abajo.", systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(detailLine(summary, me: me))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No pude saber cuál de los dos eres: elige tu nombre y lo recordaré.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func resultLine(_ result: MatchResult, _ summary: BattleLogSummary) -> String {
        guard let winner = summary.winner, let reason = summary.endReason else { return result.title }
        return "\(result.title) · \(winner) gana (\(reason.title))"
    }

    private func detailLine(_ summary: BattleLogSummary, me: String) -> String {
        let opponent = summary.opponent(of: me) ?? "rival"
        var parts = ["vs \(opponent)"]
        if let first = summary.firstPlayer { parts.append(first == me ? "empezaste tú" : "empezó \(opponent)") }
        parts.append("\(summary.turns) turnos")
        parts.append("premios \(summary.prizesTaken[me] ?? 0)–\(summary.prizesTaken[opponent] ?? 0)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Mazos y sugerencias

    private var deckPicker: some View {
        let sorted = decks.decks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let own = sorted.filter { contextArchetype != nil && decks.archetypeID(of: $0) == contextArchetype }
        let others = sorted.filter { !own.map(\.id).contains($0.id) }
        return Picker("Mi mazo", selection: $match.deckID) {
            Text("Sin mazo").tag(UUID?.none)
            if !own.isEmpty, let archetype = archetypes.item(contextArchetype) {
                Section(archetype.name) {
                    ForEach(own) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Section("Otros mazos") {
                    ForEach(others) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            } else {
                Divider()
                ForEach(others) { Text($0.name).tag(UUID?.some($0.id)) }
            }
        }
    }

    /// Pokémon que jugó el rival (según el log) y nombres ya usados.
    @ViewBuilder
    private var suggestionChips: some View {
        let fromLog = me.flatMap { me in summary.flatMap { $0.opponent(of: me) }.flatMap { summary?.pokemon[$0] } } ?? []
        let chips = match.opponentArchetype.isEmpty ? Array(fromLog.prefix(6)) : typedSuggestions
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if match.opponentArchetype.isEmpty, !fromLog.isEmpty {
                    Text("Pokémon que jugó el rival").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    ForEach(chips, id: \.self) { name in
                        Button(name) { match.opponentArchetype = name }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Acciones

    private func setUp() {
        if isNew, match.kind == nil { match.kind = lastKind }
        contextArchetype = match.deckID.flatMap(decks.deck).flatMap(decks.archetypeID)
        if let saved = match.battleLog {
            log = saved
        } else if isNew, match.currentKind == .online,
                  let clipboard = Clipboard.string, BattleLogParser.parse(clipboard) != nil {
            // Si acabas de copiar el log en PTCG Live, ya viene pegado.
            log = clipboard
        }
        detectMe()
    }

    private func detectMe() {
        guard let summary else {
            me = nil
            return
        }
        if me == nil || !summary.players.contains(me!) {
            me = summary.me(knownNames: knownNames)
        }
        applyLog()
    }

    private func applyLog() {
        guard match.currentKind == .online, let summary, let me else { return }
        match.apply(summary, me: me)
        match.battleLog = log
    }

    private func save() {
        if match.currentKind == .online {
            match.battleLog = log.isEmpty ? nil : log
            if let me, !knownNames.contains(where: { $0.caseInsensitiveCompare(me) == .orderedSame }) {
                savedUsernames = (knownNames + [me]).joined(separator: "\n")
            }
        } else {
            match.battleLog = nil
        }
        match.opponent = match.opponent.trimmingCharacters(in: .whitespaces)
        lastKind = match.currentKind
        matches.save(match)
        dismiss()
    }
}
