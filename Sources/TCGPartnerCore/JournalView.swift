import DeckKit
import SwiftUI

extension JournalKind {
    var symbol: String {
        switch self {
        case .lesson: "lightbulb.fill"
        case .guide: "book.fill"
        case .note: "note.text"
        }
    }

    var color: Color {
        switch self {
        case .lesson: .orange
        case .guide: .blue
        case .note: .gray
        }
    }
}

/// Journal de un arquetipo: anotaciones, guías y lo aprendido en cada partida.
struct JournalView: View {
    @EnvironmentObject private var journal: JournalStore
    let archetype: Archetype
    let initialEntry: UUID?
    let actions: AppActions

    @State private var selectedID: UUID?
    @State private var kindFilter: JournalKind?
    @State private var query = ""
    @CompactWidth private var compact

    private var entries: [JournalEntry] {
        journal.items.filter { $0.archetypeID == archetype.id }
    }

    private var visible: [JournalEntry] {
        JournalEntry.filter(entries, kind: kindFilter, query: query)
    }

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    /// iPhone: la lista ocupa la pantalla; al tocar una anotación se abre su editor encima.
    private var compactBody: some View {
        sidebar
            .background(AppBackground())
            .navigationTitle(archetype.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $selectedID) { id in
                JournalEditor(entryID: id, archetype: archetype, actions: actions) { selectedID = nil }
                    .background(AppBackground())
                    .navigationTitle("Journal")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { newMenu }
            }
            .onAppear {
                // Solo se abre una anotación si vienes a ella (p. ej. desde una partida).
                if let initialEntry, selectedID == nil { selectedID = initialEntry }
            }
    }

    private var fullBody: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 310)
            Divider()
            Group {
                if let selectedID, journal.item(selectedID) != nil {
                    JournalEditor(entryID: selectedID, archetype: archetype, actions: actions) {
                        self.selectedID = nil
                    }
                    .id(selectedID)
                } else {
                    emptyEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("Journal · \(archetype.name)")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { actions.select(.archetype(archetype.id)) } label: {
                    Label(archetype.name, systemImage: "chevron.left")
                }
                .help("Volver a \(archetype.name)")
            }
            ToolbarItem(placement: .primaryAction) { newMenu }
        }
        .onAppear {
            selectedID = initialEntry ?? JournalEntry.filter(entries).first?.id
        }
    }

    // MARK: - Lista

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ArchetypeIcon(archetype: archetype, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Journal").font(.title2.bold())
                    Text(archetype.name).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar", text: $query, prompt: Text("Buscar en el journal"))
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
            filterChips
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visible) { entry in
                        JournalRow(entry: entry, isSelected: entry.id == selectedID)
                            .onTapGesture { selectedID = entry.id }
                            .contextMenu {
                                Button(entry.pinned ? "Quitar de «Para recordar»" : "Fijar en «Para recordar»") {
                                    journal.update(entry.id) { $0.pinned.toggle() }
                                }
                                Divider()
                                Button("Eliminar", role: .destructive) {
                                    if selectedID == entry.id { selectedID = nil }
                                    journal.delete(entry.id)
                                }
                            }
                    }
                }
                if visible.isEmpty {
                    Text(entries.isEmpty ? "Todavía no hay anotaciones." : "Nada coincide con la búsqueda.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
        }
        .padding(16)
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            chip(nil, title: "Todo", count: entries.count)
            ForEach(JournalKind.allCases) { kind in
                chip(kind, title: kind.plural, count: entries.filter { $0.kind == kind }.count)
            }
        }
    }

    private func chip(_ kind: JournalKind?, title: String, count: Int) -> some View {
        let selected = kindFilter == kind
        return Button { kindFilter = kind } label: {
            HStack(spacing: 3) {
                Text(title)
                Text("\(count)").foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(Capsule().fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6))))
        }
        .buttonStyle(.plain)
    }

    private var newMenu: some View {
        Menu {
            ForEach(JournalKind.allCases) { kind in
                Button { create(kind) } label: {
                    Label("Nueva \(kind.title.lowercased())", systemImage: kind.symbol)
                }
            }
        } label: {
            Label("Nueva anotación", systemImage: "square.and.pencil")
        } primaryAction: {
            create(kindFilter ?? .lesson)
        }
        .help("Nueva anotación (clic) o elige el tipo (flecha)")
    }

    private var emptyEditor: some View {
        ContentUnavailableView {
            Label("Tu journal de \(archetype.name)", systemImage: "book.closed")
        } description: {
            Text("Escribe lo que aprendes en cada partida, tus guías y notas, para recordar qué hacer la próxima vez. Fija lo más importante para verlo en la página del arquetipo.")
        } actions: {
            HStack {
                ForEach(JournalKind.allCases) { kind in
                    Button { create(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                }
            }
        }
    }

    private func create(_ kind: JournalKind) {
        let entry = JournalEntry(archetypeID: archetype.id, kind: kind)
        journal.save(entry)
        query = ""
        if let filter = kindFilter, filter != kind { kindFilter = nil }
        selectedID = entry.id
    }
}

private struct JournalRow: View {
    let entry: JournalEntry
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(entry.kind.color)
                Text(entry.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                }
            }
            if !entry.preview.isEmpty {
                Text(entry.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if !entry.opponent.isEmpty {
                    PokemonIcons(names: PokemonIcon.split(entry.opponent), size: 18, alignsColumns: false)
                    Text("vs \(entry.opponent)").lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(entry.modified.formatted(.relative(presentation: .named)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.05) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Editor de una anotación. Guarda solo mientras escribes (con una pequeña espera).
private struct JournalEditor: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var matches: MatchStore
    let entryID: UUID
    let archetype: Archetype
    let actions: AppActions
    let onDelete: () -> Void

    @State private var draft: JournalEntry?
    @State private var pendingSave: Task<Void, Never>?
    @State private var confirmDelete = false
    @CompactWidth private var compact

    private var inset: CGFloat { compact ? 16 : 28 }

    var body: some View {
        Group {
            if let draft {
                editor(draft)
            } else {
                Color.clear
            }
        }
        .onAppear { draft = journal.item(entryID) }
        .onDisappear {
            flush()
            discardIfEmpty()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flushRequested)) { _ in flush() }
    }

    private var binding: Binding<JournalEntry> {
        Binding(get: { draft ?? JournalEntry(archetypeID: archetype.id) },
                set: { draft = $0; scheduleSave() })
    }

    private func editor(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar(entry)
                .padding(.horizontal, inset)
                .padding(.top, 20)
            TextField("Título", text: binding.title, prompt: Text("Título"),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, inset)
                .padding(.top, 16)
            meta(entry)
                .padding(.horizontal, inset)
                .padding(.top, 12)
            Divider().padding(.top, 14)
            TextEditor(text: binding.body)
                .font(.system(size: 15))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, inset - 5)
                .padding(.top, 14)
        }
        .confirmationDialog("¿Eliminar esta anotación?", isPresented: $confirmDelete) {
            Button("Eliminar", role: .destructive) {
                pendingSave?.cancel()
                journal.delete(entryID)
                draft = nil
                onDelete()
            }
        }
    }

    private func toolbar(_ entry: JournalEntry) -> some View {
        HStack(spacing: 8) {
            ForEach(JournalKind.allCases) { kind in
                let selected = entry.kind == kind
                Button { binding.wrappedValue.kind = kind } label: {
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .background(Capsule().fill(selected ? AnyShapeStyle(kind.color) : AnyShapeStyle(.quaternary.opacity(0.6))))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { binding.wrappedValue.pinned.toggle() } label: {
                Label(entry.pinned ? "Fijada" : "Fijar", systemImage: entry.pinned ? "pin.fill" : "pin")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .tint(entry.pinned ? .orange : nil)
            .help("Las anotaciones fijadas aparecen en «Para recordar» de la página del arquetipo")
            Button(role: .destructive) { confirmDelete = true } label: {
                Image(systemName: "trash")
            }
            .help("Eliminar anotación")
        }
    }

    private func meta(_ entry: JournalEntry) -> some View {
        HStack(spacing: 18) {
            if let id = entry.matchID, matches.item(id) != nil {
                Button("Ver partida") { actions.showMatch(id) }
                    .linkButtonStyle()
            }
            Spacer()
            Text("Editado \(entry.modified.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Una anotación que se dejó vacía no se guarda al salir de ella.
    private func discardIfEmpty() {
        guard let entry = journal.item(entryID), entry.isEmpty else { return }
        journal.delete(entryID)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        pendingSave?.cancel()
        guard var draft, let stored = journal.item(entryID), stored != draft else { return }
        if stored.title != draft.title || stored.body != draft.body || stored.opponent != draft.opponent
            || stored.kind != draft.kind {
            draft.modified = Date()
        }
        self.draft = draft
        journal.save(draft)
    }
}

/// «Para recordar»: las anotaciones fijadas, en la página del arquetipo.
struct PinnedJournalPanel: View {
    @EnvironmentObject private var journal: JournalStore
    let archetype: Archetype
    let actions: AppActions

    var body: some View {
        let pinned = JournalEntry.filter(journal.items.filter { $0.archetypeID == archetype.id && $0.pinned })
        if !pinned.isEmpty {
            Panel(title: "Para recordar", subtitle: "Lo que fijaste en tu journal") {
                Button("Abrir journal") { actions.select(.journal(archetype.id, entry: nil)) }
                    .linkButtonStyle()
            } content: {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(pinned.prefix(6)) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: entry.kind.symbol).foregroundStyle(entry.kind.color)
                                Text(entry.displayTitle).fontWeight(.semibold).lineLimit(1)
                                Spacer(minLength: 0)
                                if !entry.opponent.isEmpty {
                                    PokemonIcons(names: PokemonIcon.split(entry.opponent), size: 22, alignsColumns: false)
                                }
                            }
                            Text(entry.preview.isEmpty ? "Sin texto" : entry.preview)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(entry.kind.color.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(entry.kind.color.opacity(0.3)))
                        .contentShape(Rectangle())
                        .onTapGesture { actions.select(.journal(archetype.id, entry: entry.id)) }
                        .help("Abrir en el journal")
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
        }
    }
}

/// Para elegir el estilo de una etiqueta según el ancho.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(Label($0).labelStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
