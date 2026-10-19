import DeckKit
import SwiftUI

/// Clave del jugador actual (UUID). Es el que se muestra en la barra lateral y se propone al imprimir.
let currentPlayerKey = "print.selectedPlayer"

/// Elegir un jugador guardado y editar sus datos. Se usa en Configuración y en la hoja de impresión.
/// Va dentro de una `Section` de un `Form`.
struct PlayerFields: View {
    @EnvironmentObject private var playerStore: PlayerStore
    @AppStorage(currentPlayerKey) private var selectedPlayerID = ""
    /// Texto de la opción sin jugador («En blanco», «Ninguno»).
    var blankOption: String
    @State private var playerToDelete: Player?

    private var selectedPlayer: Player? {
        UUID(uuidString: selectedPlayerID).flatMap(playerStore.player)
    }

    var body: some View {
        Group {
            Picker("Jugador", selection: $selectedPlayerID) {
                Text(blankOption).tag("")
                if !playerStore.players.isEmpty { Divider() }
                ForEach(playerStore.sorted) { player in
                    Text(player.displayName).tag(player.id.uuidString)
                }
            }
            if let player = selectedPlayer {
                TextField("Nombre", text: binding(player, \.name), prompt: Text("Nombre y apellido"))
                TextField("Player ID", text: binding(player, \.playerID), prompt: Text("1234567"))
                birthDateRow(player)
            }
            HStack {
                Button {
                    selectedPlayerID = playerStore.add().id.uuidString
                } label: {
                    Label("Nuevo jugador", systemImage: "person.badge.plus")
                }
                Spacer()
                if let player = selectedPlayer {
                    Button(role: .destructive) {
                        playerToDelete = player
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                    .help("Eliminar a este jugador de los guardados")
                }
            }
            .buttonStyle(.borderless)
        }
        .confirmationDialog("¿Eliminar a «\(playerToDelete?.displayName ?? "")» de los jugadores guardados?",
                            isPresented: Binding(get: { playerToDelete != nil }, set: { if !$0 { playerToDelete = nil } }),
                            presenting: playerToDelete) { player in
            Button("Eliminar", role: .destructive) {
                playerStore.delete(player.id)
                if selectedPlayerID == player.id.uuidString { selectedPlayerID = "" }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Sus datos ya no aparecerán en la lista. Los mazos y las partidas no se modifican.")
        }
    }

    @ViewBuilder
    private func birthDateRow(_ player: Player) -> some View {
        if let birth = player.birthDate {
            DatePicker("Fecha de nacimiento",
                       selection: Binding(get: { birth }, set: { date in playerStore.update(player.id) { $0.birthDate = date } }),
                       in: ...Date(), displayedComponents: .date)
            LabeledContent("División") {
                HStack {
                    Text(AgeDivision.forBirthDate(birth).title)
                    Button {
                        playerStore.update(player.id) { $0.birthDate = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Quitar la fecha de nacimiento")
                }
            }
        } else {
            LabeledContent("Fecha de nacimiento") {
                Button("Añadir") {
                    playerStore.update(player.id) {
                        $0.birthDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
                    }
                }
            }
        }
    }

    /// Edita un dato del jugador; se guarda al momento en players.json.
    private func binding(_ player: Player, _ keyPath: WritableKeyPath<Player, String>) -> Binding<String> {
        Binding(get: { playerStore.player(player.id)?[keyPath: keyPath] ?? player[keyPath: keyPath] },
                set: { value in playerStore.update(player.id) { $0[keyPath: keyPath] = value } })
    }
}
