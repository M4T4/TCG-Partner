import DeckKit
import Foundation

/// Los borrados pendientes de contar a la nube, en `~/Library/Application Support/TCGPartner/deleted.json`.
/// Los stores anotan aquí cada elemento que borran; la sincronización los sube y luego los olvida.
@MainActor
final class DeletionLogStore {
    static let shared = DeletionLogStore()

    private(set) var log: DeletionLog
    let file: URL

    init(file: URL = DeckStore.supportFolder.appendingPathComponent("deleted.json")) {
        self.file = file
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        log = (try? decoder.decode(DeletionLog.self, from: Data(contentsOf: file))) ?? DeletionLog()
    }

    func record(table: String, id: UUID) {
        log.record(table: table, id: id)
        save()
    }

    func remove(_ done: [Tombstone]) {
        log.remove(done)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(log).write(to: file, options: .atomic)
        } catch {
            // No es grave: en el peor caso el borrado no llega a los otros equipos.
            print("No se pudo guardar deleted.json: \(error.localizedDescription)")
        }
    }
}
