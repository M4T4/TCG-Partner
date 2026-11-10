import DeckKit
import SwiftUI

/// Descarga los iconos de Pokémon de Limitless y los guarda en disco.
actor PokemonIconService {
    static let shared = PokemonIconService()

    nonisolated static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGPartner/icons", isDirectory: true)
    }

    /// Nombres que Limitless no tiene (no se vuelven a pedir en esta sesión).
    private var missing: Set<String> = []
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Archivo local del icono de un Pokémon (prueba el nombre completo y luego la primera palabra).
    func file(for name: String) async -> URL? {
        for slug in PokemonIcon.candidates(name) {
            if let file = await file(slug: slug) { return file }
        }
        return nil
    }

    private func file(slug: String) async -> URL? {
        let file = Self.cacheDirectory.appendingPathComponent("\(slug).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if missing.contains(slug) { return nil }
        if let task = inFlight[slug] { return await task.value }
        let task = Task { () -> URL? in
            guard let (data, response) = try? await session.data(from: PokemonIcon.url(slug: slug)),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.mimeType?.hasPrefix("image/") == true,
                  (try? data.write(to: file, options: .atomic)) != nil else { return nil }
            return file
        }
        inFlight[slug] = task
        let result = await task.value
        inFlight[slug] = nil
        if result == nil { missing.insert(slug) }
        return result
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        missing = []
    }
}

/// Icono de un Pokémon (sprite pixel art de Limitless). Si no existe, un círculo con la inicial.
struct PokemonIconView: View {
    let name: String
    var size: CGFloat = 24
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.none) // pixel art: sin suavizar
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                Circle()
                    .fill(.quaternary)
                    .overlay(Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.secondary))
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .help(name)
        .task(id: name) {
            failed = false
            if let file = await PokemonIconService.shared.file(for: name),
               let loaded = CardImageMemory.image(at: file) {
                image = loaded
            } else {
                image = nil
                failed = true
            }
        }
    }
}

/// 1 o 2 iconos juntos, como en Limitless.
struct PokemonIcons: View {
    let names: [String]
    var size: CGFloat = 24
    /// Reserva el ancho de dos iconos para que las columnas queden alineadas; `false` ocupa solo lo necesario.
    var alignsColumns = true

    var body: some View {
        HStack(spacing: -size * 0.12) {
            ForEach(Array(names.prefix(2).enumerated()), id: \.offset) { _, name in
                PokemonIconView(name: name, size: size)
            }
        }
        .frame(minWidth: alignsColumns ? size * 2 - size * 0.12 : nil, alignment: .leading)
    }
}

/// Elegir 1 o 2 Pokémon para los iconos, con vista previa y sugerencias.
struct IconPicker: View {
    @Binding var names: [String]
    /// Pokémon sugeridos (por ejemplo, los de los mazos relacionados).
    var suggestions: [String] = []
    /// Lo que se muestra si se deja vacío (heredado del arquetipo, del nombre…).
    var placeholder: [String] = []

    // Cada campo guarda su propio texto: así no se mueven ni se borran mientras escribes.
    @State private var first = ""
    @State private var second = ""

    private func load() {
        first = names.first ?? ""
        second = names.count > 1 ? names[1] : ""
    }

    /// Pasa los campos a `names`. Si escribes solo el segundo partiendo de los heredados,
    /// el primero se rellena con el heredado (ver `PokemonIcon.combine`).
    private func commit() {
        let result = PokemonIcon.combine(first: first, second: second, previous: names, inherited: placeholder)
        if result.first != first.trimmingCharacters(in: .whitespaces) { first = result.first }
        if result.names != names { names = result.names }
    }

    /// Las sugerencias funcionan igual: si no había iconos propios, la elegida se suma al heredado.
    private func toggle(_ name: String) {
        if names.contains(name) {
            names.removeAll { $0 == name }
        } else if names.isEmpty, let base = placeholder.first, base.caseInsensitiveCompare(name) != .orderedSame {
            names = [base, name]
        } else {
            names = Array((names + [name]).suffix(2))
        }
        load()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PokemonIcons(names: names.isEmpty ? placeholder : names, size: 56)
                .onAppear(perform: load)
                .frame(width: 104, height: 56)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            VStack(alignment: .leading, spacing: 8) {
                TextField("Pokémon principal", text: $first, prompt: Text(placeholder.first ?? "Ej. Alakazam"))
                    .onChange(of: first) { commit() }
                TextField("Segundo Pokémon", text: $second, prompt: Text(placeholder.dropFirst().first ?? "Opcional · Ej. Dusknoir"))
                    .onChange(of: second) { commit() }
                if !names.isEmpty {
                    Button(placeholder.isEmpty ? "Quitar iconos" : "Usar los heredados") {
                        names = []
                        load()
                    }
                        .linkButtonStyle()
                        .font(.caption)
                }
            }
        }
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pokémon de sus mazos").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions.prefix(10), id: \.self) { name in
                            Button { toggle(name) } label: {
                                HStack(spacing: 4) {
                                    PokemonIconView(name: name, size: 20)
                                    Text(name).lineLimit(1)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(names.contains(name) ? .accentColor : nil)
                        }
                    }
                }
            }
        }
    }
}

/// Hoja para elegir los iconos de una carpeta o de un mazo.
struct IconsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var names: [String]
    let inherited: [String]
    let inheritedFrom: String?
    let suggestions: [String]
    let onSave: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    IconPicker(names: $names, suggestions: suggestions, placeholder: inherited)
                } header: {
                    Text(title)
                } footer: {
                    if let inheritedFrom {
                        Text("Si lo dejas vacío se usan los iconos de \(inheritedFrom).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    onSave(names)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .sheetFrame(width: 520, height: 340)
    }
}
