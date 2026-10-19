import DeckKit
import SwiftUI

/// Configuración: jugador actual, mis datos, cuentas de PTCG Live, tema y datos de la app.
struct SettingsView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var playerStore: PlayerStore
    @AppStorage(currentPlayerKey) private var currentPlayerID = ""
    @AppStorage("ptcgl.usernames") private var savedUsernames = ""
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @State private var newUsername = ""
    @State private var cacheCleared = false

    private var usernames: [String] {
        savedUsernames.split(separator: "\n").map(String.init)
    }

    private var currentPlayer: Player? {
        UUID(uuidString: currentPlayerID).flatMap(playerStore.player)
    }

    var body: some View {
        Form {
            Section {
                PlayerFields(blankOption: "Ninguno")
            } header: {
                Text("Jugador actual y mis datos")
            } footer: {
                Text("El jugador actual aparece abajo en la barra lateral y se propone al imprimir una lista. Si varias personas usan la app, cada una puede guardar sus datos y cambiar de jugador aquí.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(usernames, id: \.self) { name in
                    HStack {
                        Label(name, systemImage: "globe")
                        Spacer()
                        Button {
                            savedUsernames = usernames.filter { $0 != name }.joined(separator: "\n")
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Quitar este usuario")
                    }
                }
                HStack {
                    TextField("Agregar usuario", text: $newUsername, prompt: Text("Ej. Matt_277"))
                        .onSubmit(addUsername)
                    Button("Agregar", action: addUsername)
                        .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Mis usuarios de PTCG Live")
            } footer: {
                Text("Con estos nombres la app sabe cuál de los dos jugadores eres al leer un battle log. También se agregan solos al registrar una partida.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tema") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(AppTheme.allCases) { option in
                        ThemeSwatch(theme: option, isSelected: option == theme) { theme = option }
                    }
                }
                .padding(.vertical, 6)
                Picker("Apariencia", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Datos") {
                LabeledContent("Mazos guardados", value: "\(decks.decks.count)")
                LabeledContent("Jugadores guardados", value: "\(playerStore.players.count)")
                HStack {
                    Button("Mostrar datos en Finder") {
                        NSWorkspace.shared.open(DeckStore.supportFolder)
                    }
                    Button(cacheCleared ? "Caché vaciada" : "Vaciar caché de imágenes") {
                        Task {
                            await CardImageService.shared.clearCache()
                            await PokemonIconService.shared.clearCache()
                        }
                        cacheCleared = true
                    }
                    .disabled(cacheCleared)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(AppBackground())
        .navigationTitle("Configuración")
    }

    private func addUsername() {
        let name = newUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !usernames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        savedUsernames = (usernames + [name]).joined(separator: "\n")
        newUsername = ""
    }
}

/// Muestra de un tema: degradado con su icono y nombre.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [theme.swatch, theme.secondary ?? theme.swatch.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 54)
                    .overlay {
                        Image(systemName: theme.symbol)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, theme.swatch)
                                .padding(5)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.primary : .clear, lineWidth: 2)
                    }
                Text(theme.title)
                    .font(.caption.weight(isSelected ? .bold : .regular))
            }
        }
        .buttonStyle(.plain)
        .help("Tema \(theme.title)")
    }
}

/// Pie de la barra lateral: jugador actual y acceso a Configuración.
struct SidebarFooter: View {
    @EnvironmentObject private var playerStore: PlayerStore
    @AppStorage(currentPlayerKey) private var currentPlayerID = ""
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var player: Player? {
        UUID(uuidString: currentPlayerID).flatMap(playerStore.player)
    }

    private var initials: String {
        let words = (player?.name ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: action) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(LinearGradient(colors: [theme.swatch, theme.secondary ?? theme.swatch.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                        .overlay(Text(initials).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player?.displayName ?? "Sin jugador")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(player.map { $0.playerID.isEmpty ? "Sin Player ID" : "ID \($0.playerID)" } ?? "Elige quién eres")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Configuración: jugador actual, mis datos y tema")
            .padding(8)
        }
    }
}
