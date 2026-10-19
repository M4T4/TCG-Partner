import DeckKit
import SwiftUI

/// Detalle de un arquetipo: récord, carpetas, mazos y partidas recientes.
struct ArchetypeView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var journal: JournalStore
    let archetype: Archetype
    let actions: AppActions

    private var archetypeDecks: [Deck] { decks.decks(ofArchetype: archetype.id) }

    /// El mazo del arquetipo con más partidas, para proponerlo al registrar.
    private var mostPlayedDeck: UUID? {
        let counts = Dictionary(grouping: archetypeMatches.compactMap(\.deckID), by: { $0 }).mapValues(\.count)
        return archetypeDecks.max { (counts[$0.id] ?? 0, $1.modified) < (counts[$1.id] ?? 0, $0.modified) }?.id
    }

    private var archetypeMatches: [MatchRecord] {
        let ids = Set(archetypeDecks.map(\.id))
        return matches.items.filter { $0.deckID.map(ids.contains) ?? false }
    }

    var body: some View {
        let analytics = Analytics(decks: decks, archetypes: archetypes, matches: archetypeMatches)
        let stats = archetypeMatches.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    ArchetypeIcon(archetype: archetype, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(archetype.name).font(.largeTitle.bold())
                        Text("\(decks.folders(of: archetype.id).count) carpetas · \(archetypeDecks.count) mazos · \(stats.total) partidas")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let notes = journal.items.filter { $0.archetypeID == archetype.id }.count
                    Button { actions.select(.journal(archetype.id, entry: nil)) } label: {
                        Label(notes > 0 ? "Journal · \(notes)" : "Journal", systemImage: "book.closed")
                    }
                    .help("Tus anotaciones, guías y lo que aprendes en cada partida")
                    Button("Editar…") { actions.editArchetype(archetype) }
                    Menu {
                        Button { actions.logMatchOfKind(mostPlayedDeck, .online) } label: {
                            Label("Partida en PTCG Live…", systemImage: MatchKind.online.symbol)
                        }
                        Button { actions.logMatchOfKind(mostPlayedDeck, .inPerson) } label: {
                            Label("Partida presencial…", systemImage: MatchKind.inPerson.symbol)
                        }
                    } label: {
                        Label("Registrar partida", systemImage: "plus.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                    .disabled(archetypeDecks.isEmpty)
                }

                PinnedJournalPanel(archetype: archetype, actions: actions)

                HStack(alignment: .top, spacing: 20) {
                    Panel(title: "Récord del arquetipo") {
                        if stats.total == 0 {
                            Text("Sin partidas todavía.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 20)
                        } else {
                            PieChart(slices: [
                                PieSlice(label: "Victorias", value: Double(stats.wins), color: .green),
                                PieSlice(label: "Derrotas", value: Double(stats.losses), color: .red),
                                PieSlice(label: "Empates", value: Double(stats.ties), color: .gray),
                            ].filter { $0.value > 0 }, title: percentText(stats.winRate), subtitle: stats.record)
                                .frame(height: 210)
                                .padding([.horizontal, .bottom], 16)
                        }
                    }
                    .frame(width: 300)

                    Panel(title: "Mazos", subtitle: "Ordenados por partidas jugadas") {
                        if archetypeDecks.isEmpty {
                            Text("Arrastra mazos o carpetas sobre «\(archetype.name)» en la barra lateral.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(analytics.deckPerformance.filter { archetypeDecks.map(\.id).contains($0.deck.id) }) { row in
                                    HStack(spacing: 10) {
                                        PokemonIcons(names: decks.icons(for: row.deck, archetypes: archetypes), size: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.deck.name).fontWeight(.medium)
                                            Text(row.deck.folder.map { "Carpeta «\($0)»" } ?? "Sin carpeta")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(row.stats.total > 0 ? row.stats.record : "—").monospacedDigit()
                                        WinRateBar(rate: row.stats.winRate)
                                        StatusBadge(status: row.deck.currentStatus)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture { actions.select(.deck(row.deck.id)) }
                                    Divider()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                }

                let matchups = Matchup.table(archetypeMatches)
                if !matchups.isEmpty {
                    Panel(title: "Win rate por matchup", subtitle: "Tu porcentaje de victoria contra cada mazo rival") {
                        MatchupTable(matchups: matchups)
                    }
                }

                let recent = archetypeMatches.sorted { $0.date > $1.date }.prefix(6)
                if !recent.isEmpty {
                    Panel(title: "Partidas recientes", subtitle: "Haz clic en una partida para ver todos sus datos") {
                        Button("Historial completo") { actions.select(.matches) }
                            .buttonStyle(.link)
                    } content: {
                        MatchList(matches: Array(recent), onSelect: { actions.showMatch($0.id) })
                    }
                }

                if !archetype.notes.isEmpty {
                    Panel(title: "Notas") {
                        Text(archetype.notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .bottom], 16)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle(archetype.name)
    }
}

/// Tabla de matchups: récord y porcentaje de victoria contra cada mazo rival.
struct MatchupTable: View {
    let matchups: [Matchup]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Mazo rival").frame(maxWidth: .infinity, alignment: .leading)
                Text("Partidas").frame(width: 64, alignment: .trailing)
                Text("V - D - E").frame(width: 80, alignment: .trailing)
                Text("Win rate").frame(width: 190, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ForEach(matchups, id: \.opponent) { row in
                Divider()
                MatchupRow(matchup: row)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct MatchupRow: View {
    let matchup: Matchup

    private var stats: MatchStats { matchup.stats }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if matchup.opponent.isEmpty {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .frame(width: 58, alignment: .leading)
                    Text("Sin anotar").foregroundStyle(.secondary)
                } else {
                    PokemonIcons(names: PokemonIcon.split(matchup.opponent), size: 30)
                    Text(matchup.opponent).fontWeight(.medium)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(stats.total)").monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Text("\(stats.wins)-\(stats.losses)-\(stats.ties)").monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            MatchupBar(stats: stats)
                .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(winRateColor(stats.winRate).opacity(0.06))
    }
}

/// Barra dividida en victorias (verde), empates (gris) y derrotas (rojo), con el porcentaje.
private struct MatchupBar: View {
    let stats: MatchStats

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let total = CGFloat(max(stats.total, 1))
                HStack(spacing: 0) {
                    Rectangle().fill(.green).frame(width: geo.size.width * CGFloat(stats.wins) / total)
                    Rectangle().fill(.gray).frame(width: geo.size.width * CGFloat(stats.ties) / total)
                    Rectangle().fill(.red).frame(width: geo.size.width * CGFloat(stats.losses) / total)
                }
                .clipShape(Capsule())
            }
            .frame(width: 110, height: 7)
            Text(percentText(stats.winRate))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(winRateColor(stats.winRate))
        }
    }
}

/// Crear o editar un arquetipo.
struct ArchetypeEditor: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @Environment(\.dismiss) private var dismiss

    @State var archetype: Archetype
    let isNew: Bool
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nombre", text: $archetype.name, prompt: Text("Ej. Alakazam"))
                    // Círculos propios: el control segmentado pinta las imágenes de un solo color.
                    LabeledContent("Color") {
                        HStack(spacing: 8) {
                            ForEach(ArchetypeColor.allCases) { option in
                                Button { archetype.color = option } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.primary, lineWidth: archetype.color == option ? 2 : 0)
                                            .padding(-3))
                                }
                                .buttonStyle(.plain)
                                .help(option.rawValue)
                            }
                        }
                    }
                }
                Section {
                    IconPicker(names: Binding(get: { archetype.icons ?? [] },
                                              set: { archetype.icons = $0.isEmpty ? nil : $0 }),
                               suggestions: decks.pokemonSuggestions(in: decks.decks(ofArchetype: archetype.id)),
                               placeholder: PokemonIcon.split(archetype.name))
                } header: {
                    Text("Iconos")
                } footer: {
                    Text("Como en Limitless: 1 o 2 Pokémon. Si lo dejas vacío se usa el nombre del arquetipo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Notas") {
                    TextField("Notas", text: $archetype.notes, prompt: Text("Plan de juego, matchups…"), axis: .vertical)
                        .lineLimit(3...6)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Eliminar", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Crear" : "Guardar") {
                    archetype.name = archetype.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    archetypes.save(archetype)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(archetype.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .confirmationDialog("¿Eliminar el arquetipo «\(archetype.name)»?", isPresented: $confirmDelete) {
            Button("Eliminar arquetipo", role: .destructive) {
                decks.detachArchetype(archetype.id)
                archetypes.delete(archetype.id)
                dismiss()
            }
        } message: {
            Text("Sus carpetas y mazos no se borran: quedan sin arquetipo.")
        }
    }
}
