import DeckKit
import SwiftUI

/// Qué abre la hoja de lista: un mazo nuevo o la edición de uno existente.
enum DeckEditorRequest: Identifiable {
    case create(prefill: String, at: DeckLocation)
    case edit(Deck.ID)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let id): id.uuidString
        }
    }

    /// Mazo nuevo con el portapapeles ya pegado si contiene una lista.
    @MainActor static func fromClipboard(at location: DeckLocation) -> DeckEditorRequest {
        let text = Clipboard.string ?? ""
        return .create(prefill: DeckParser.parse(text).isEmpty ? "" : text, at: location)
    }
}

/// Hoja para pegar (o corregir) una lista de Limitless con un resumen en vivo.
struct PasteDeckSheet: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @Environment(\.dismiss) private var dismiss
    let request: DeckEditorRequest

    @State private var name = ""
    @State private var list = ""
    @State private var folderChoice = FolderChoice.none
    @State private var newFolderName = ""

    /// Dónde va el mazo dentro de su arquetipo.
    private enum FolderChoice: Hashable {
        /// Directo en el arquetipo, sin carpeta.
        case none
        case folder(String)
        case new
    }

    /// Arquetipo del mazo nuevo: el pedido o el de la carpeta pedida. `nil` al editar o si no hay.
    private var targetArchetype: Archetype? {
        guard case .create(_, let location) = request else { return nil }
        switch location {
        case .archetype(let id): return archetypes.item(id)
        case .folder(let folder): return archetypes.item(store.folderArchetypes[folder])
        case .loose: return nil
        }
    }

    private var trimmedFolderName: String { newFolderName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var folderNameTaken: Bool {
        store.folders.contains { $0.localizedCaseInsensitiveCompare(trimmedFolderName) == .orderedSame }
    }

    private var canSave: Bool {
        guard !parsed.isEmpty else { return false }
        if targetArchetype != nil, folderChoice == .new { return !trimmedFolderName.isEmpty && !folderNameTaken }
        return true
    }

    private var parsed: ParsedDeck { DeckParser.parse(list) }

    private var title: String {
        switch request {
        case .edit: "Editar lista"
        case .create where targetArchetype != nil: "Nuevo mazo en «\(targetArchetype!.name)»"
        case .create(_, .folder(let folder)): "Nuevo mazo en «\(folder)»"
        case .create: "Nuevo mazo"
        }
    }

    private var isEditing: Bool {
        if case .edit = request { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())

            TextField("Nombre del mazo", text: $name, prompt: Text(parsed.suggestedName))
                .textFieldStyle(.roundedBorder)

            if let archetype = targetArchetype {
                folderPicker(archetype)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Lista").font(.headline)
                    Spacer()
                    Button("Pegar del portapapeles") {
                        list = Clipboard.string ?? list
                    }
                    .linkButtonStyle()
                }
                TextEditor(text: $list)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.textBackground))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    .overlay(alignment: .topLeading) {
                        if list.isEmpty {
                            Text("Copia la lista en Limitless («Export» → «Copy to clipboard») y pégala aquí.\n\nPokémon: 12\n4 Dreepy TWM 128\n…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(11)
                                .allowsHitTesting(false)
                        }
                    }
            }

            summary

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Guardar" : "Crear mazo") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 620)
        .onAppear(perform: load)
    }

    /// Elegir si el mazo va directo en el arquetipo, en una de sus carpetas o en una carpeta nueva.
    private func folderPicker(_ archetype: Archetype) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Carpeta", selection: $folderChoice) {
                Text("Sin carpeta (directo en «\(archetype.name)»)").tag(FolderChoice.none)
                let folders = store.folders(of: archetype.id)
                if !folders.isEmpty {
                    Divider()
                    ForEach(folders, id: \.self) { folder in
                        Label(folder, systemImage: "folder").tag(FolderChoice.folder(folder))
                    }
                }
                Divider()
                Label("Carpeta nueva…", systemImage: "folder.badge.plus").tag(FolderChoice.new)
            }
            if folderChoice == .new {
                TextField("Nombre de la carpeta nueva", text: $newFolderName, prompt: Text("Ej. Regionales"))
                    .textFieldStyle(.roundedBorder)
                if folderNameTaken {
                    Text("Ya existe una carpeta llamada «\(trimmedFolderName)».")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if parsed.isEmpty {
            Label("Todavía no hay cartas reconocidas.", systemImage: "rectangle.stack")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(parsed.summary, systemImage: parsed.isStandardSize ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(parsed.isStandardSize ? Color.green : Color.orange)
                if !parsed.unparsedLines.isEmpty {
                    Text("Líneas no reconocidas: " + parsed.unparsedLines.prefix(4).map { "«\($0)»" }.joined(separator: ", ")
                         + (parsed.unparsedLines.count > 4 ? "…" : ""))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
    }

    private func load() {
        switch request {
        case .create(let prefill, let location):
            list = prefill
            if case .folder(let folder) = location { folderChoice = .folder(folder) }
        case .edit(let id):
            guard let deck = store.deck(id) else { return }
            name = deck.name
            list = deck.list
        }
    }

    private func save() {
        switch request {
        case .create(_, let location):
            var target = location
            if let archetype = targetArchetype {
                switch folderChoice {
                case .none:
                    target = .archetype(archetype.id)
                case .folder(let folder):
                    target = .folder(folder)
                case .new:
                    guard let folder = store.createFolder(named: newFolderName, archetype: archetype.id) else { return }
                    target = .folder(folder)
                }
            }
            store.create(name: name, list: list, at: target)
        case .edit(let id):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            store.update(id) {
                $0.list = list
                if !trimmed.isEmpty { $0.name = trimmed }
            }
        }
        dismiss()
    }
}
