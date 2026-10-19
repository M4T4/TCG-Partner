import AppKit
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
    static func fromClipboard(at location: DeckLocation) -> DeckEditorRequest {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
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

    private var parsed: ParsedDeck { DeckParser.parse(list) }

    private var title: String {
        switch request {
        case .edit: "Editar lista"
        case .create(_, .folder(let folder)): "Nuevo mazo en «\(folder)»"
        case .create(_, .archetype(let id)): "Nuevo mazo en «\(archetypes.item(id)?.name ?? "arquetipo")»"
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

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Lista").font(.headline)
                    Spacer()
                    Button("Pegar del portapapeles") {
                        list = NSPasteboard.general.string(forType: .string) ?? list
                    }
                    .buttonStyle(.link)
                }
                TextEditor(text: $list)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
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
                    .disabled(parsed.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 620)
        .onAppear(perform: load)
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
        case .create(let prefill, _):
            list = prefill
        case .edit(let id):
            guard let deck = store.deck(id) else { return }
            name = deck.name
            list = deck.list
        }
    }

    private func save() {
        switch request {
        case .create(_, let location):
            store.create(name: name, list: list, at: location)
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
