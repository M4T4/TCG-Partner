import DeckKit
import SwiftUI

/// Detalle de un mazo: cabecera con contadores y la lista como cuadrícula de cartas.
struct DeckView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    let deck: Deck
    let onEditList: () -> Void
    let onPrint: () -> Void
    let onLogMatch: () -> Void
    let onEditIcons: () -> Void
    @State private var copied = false
    @CompactWidth private var compact

    private var parsed: ParsedDeck { deck.parsed }

    /// En iPhone, 3 cartas por fila.
    private var columns: [GridItem] {
        compact ? Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            : [GridItem(.adaptive(minimum: 118, maximum: 170), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(DeckSection.allCases, id: \.self) { section in
                    let cards = parsed.entries(in: section)
                    if !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: section.symbol).foregroundStyle(section.color)
                                Text(section.title).font(.title3.bold())
                                Text("\(parsed.count(in: section))")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 10 : 14) {
                                ForEach(cards) { CardTile(entry: $0) }
                            }
                        }
                    }
                }
                notes
            }
            .padding(compact ? 16 : 24)
        }
        .background(AppBackground())
        #if os(iOS)
        // El nombre se edita en la cabecera; arriba solo queda pequeño.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if compact { compactToolbar } else { fullToolbar }
        }
    }

    private func copyList() {
        store.copySelectedList()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// iPhone: Registrar partida a la vista; lo demás en el menú «…».
    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onLogMatch) {
                Label("Registrar partida", systemImage: "plus.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(action: onEditList) { Label("Editar lista", systemImage: "square.and.pencil") }
                Button(action: copyList) { Label(copied ? "Copiada" : "Copiar lista", systemImage: copied ? "checkmark" : "doc.on.doc") }
                Button(action: onPrint) { Label("PDF para imprimir", systemImage: "printer") }
                Button(action: onEditIcons) { Label("Iconos", systemImage: "face.smiling") }
            } label: {
                Label("Más", systemImage: "ellipsis")
            }
        }
    }

    @ToolbarContentBuilder
    private var fullToolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onLogMatch) {
                    Label("Registrar partida", systemImage: "plus.circle")
                }
                .help("Registrar una partida con este mazo (⌘R)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onPrint) {
                    Label("Imprimir", systemImage: "printer")
                }
                .help("Imprimir la lista o exportarla como PDF (⌘P)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onEditList) {
                    Label("Editar lista", systemImage: "square.and.pencil")
                }
                .help("Editar la lista del mazo")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: copyList) {
                    Label(copied ? "Copiada" : "Copiar lista", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copiar la lista en formato Limitless / PTCG Live (⇧⌘C)")
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onEditIcons) {
                    PokemonIcons(names: store.icons(for: deck, archetypes: archetypes), size: compact ? 40 : 52)
                }
                .buttonStyle(.plain)
                .help("Cambiar los iconos del mazo")
                TextField("Nombre", text: Binding(get: { deck.name },
                                                  set: { name in store.update(deck.id) { $0.name = name } }))
                    .textFieldStyle(.plain)
                    .font(compact ? .title.bold() : .largeTitle.bold())
            }
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CountChip(text: parsed.totalCount == 1 ? "1 carta" : "\(parsed.totalCount) cartas",
                          symbol: parsed.isStandardSize ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                          color: parsed.isStandardSize ? .green : .orange)
                ForEach(DeckSection.allCases, id: \.self) { section in
                    CountChip(text: "\(parsed.count(in: section)) \(section.title)", symbol: section.symbol, color: section.color)
                }
            }
            }
            .scrollDisabled(!compact)
            HStack(spacing: 8) {
                Menu {
                    Picker("Estado", selection: Binding(get: { deck.currentStatus },
                                                        set: { status in store.update(deck.id) { $0.status = status } })) {
                        ForEach(DeckStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    StatusBadge(status: deck.currentStatus)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Cambiar el estado del mazo")
                if let archetype = archetypes.item(store.archetypeID(of: deck)) {
                    Badge(text: archetype.name, color: archetype.color.color)
                }
                let record = matches.items.filter { $0.deckID == deck.id }.stats
                if record.total > 0 {
                    CountChip(text: "\(record.record) · \(percentText(record.winRate))", symbol: "trophy",
                              color: winRateColor(record.winRate))
                }
            }
            if !parsed.isStandardSize {
                Text("Un mazo de Estándar debe tener 60 cartas.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if !parsed.unparsedLines.isEmpty {
                Button {
                    onEditList()
                } label: {
                    Label("\(parsed.unparsedLines.count) líneas de la lista no se reconocieron. Revisar…",
                          systemImage: "exclamationmark.bubble")
                }
                .linkButtonStyle()
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notas").font(.title3.bold())
            TextField("Estrategia, matchups, cambios pendientes…",
                      text: Binding(get: { deck.notes }, set: { text in store.update(deck.id) { $0.notes = text } }),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
    }
}

struct CountChip: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

/// Carta en la cuadrícula con su cantidad; al hacer clic se ve en grande.
struct CardTile: View {
    let entry: CardEntry
    @State private var showDetail = false
    @State private var hovering = false

    var body: some View {
        CardImage(entry: entry)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 8 : 3, y: hovering ? 4 : 2)
            .overlay(alignment: .bottomTrailing) {
                Text("×\(entry.count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .padding(6)
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { showDetail = true }
            .help("\(entry.count) × \(entry.name)")
            .popover(isPresented: $showDetail, arrowEdge: .trailing) {
                VStack(spacing: 10) {
                    CardImage(entry: entry, size: .large)
                        .frame(width: 320)
                    Text("\(entry.count) × \(entry.name)").font(.headline)
                    if let set = entry.setCode, let number = entry.number {
                        Text("\(set) \(number)").foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
    }
}
