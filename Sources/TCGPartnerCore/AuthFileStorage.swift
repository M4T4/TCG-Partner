import Auth
import Foundation

#if os(macOS)
/// Guarda la sesión de Supabase en un archivo en lugar del llavero (solo en Mac).
///
/// Sin un Team ID de Apple, el llavero ata el permiso al hash exacto del binario, que cambia en cada
/// compilación, y pedía la contraseña tras cada `build-app.sh`. El archivo está en
/// `~/Library/Application Support/TCGPartner/auth/`, con permisos solo para tu usuario (carpeta 700,
/// archivos 600). El token solo da acceso a tus propios datos de TCG Partner.
///
/// En iPhone se sigue usando el llavero: allí la app tiene su propio espacio y no pasa esto.
struct AuthFileStorage: AuthLocalStorage {
    let folder: URL

    init(folder: URL = DeckStore.supportFolder.appendingPathComponent("auth", isDirectory: true)) {
        self.folder = folder
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return folder.appendingPathComponent(String(safe))
    }

    func store(key: String, value: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let url = file(key)
        try value.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func retrieve(key: String) throws -> Data? {
        let url = file(key)
        if FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        // Las versiones anteriores la guardaban en el llavero: se pasa al archivo una sola vez
        // (macOS puede pedir la contraseña esta última vez) y se borra del llavero.
        let keychain = KeychainLocalStorage()
        guard let data = try? keychain.retrieve(key: key) else { return nil }
        try store(key: key, value: data)
        try? keychain.remove(key: key)
        return data
    }

    func remove(key: String) throws {
        let url = file(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
#endif
