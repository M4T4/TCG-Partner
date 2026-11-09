import DeckKit
import SwiftUI

enum CardImageSize: String, Sendable {
    /// ~245 px de ancho, para la cuadrícula.
    case small
    /// ~730 px de ancho, para el zoom.
    case large
}

/// Lo mínimo para buscar la imagen de una carta (Sendable, para pasarlo al actor).
struct CardRef: Sendable, Hashable {
    let key: String
    let name: String
    let searchName: String
    let setCode: String?
    let number: String?
    let paddedNumber: String?

    init(_ entry: CardEntry) {
        key = entry.cardKey
        name = entry.name
        searchName = entry.searchName
        setCode = entry.setCode
        number = entry.number
        paddedNumber = entry.paddedNumber
    }
}

/// Descarga las imágenes de las cartas y las guarda en disco.
///
/// Orden de búsqueda: archivo en caché → CDN de Limitless (URL directa por set y número) →
/// API de pokemontcg.io por set y número → la misma API por nombre. Lo que no se encuentra
/// se recuerda 7 días para no repetir peticiones.
actor CardImageService {
    static let shared = CardImageService()

    nonisolated static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGPartner/cards", isDirectory: true)
    }

    nonisolated static var lookupsFile: URL {
        DeckStore.supportFolder.appendingPathComponent("lookups.json")
    }

    private struct Lookup: Codable {
        /// URLs encontradas en la API (las de Limitless no hace falta guardarlas: se deducen).
        var small: URL?
        var large: URL?
        /// Cuándo falló todo por última vez.
        var failedAt: Date?
    }

    private static let retryAfter: TimeInterval = 7 * 24 * 3600
    private static let maxConcurrent = 4

    private var lookups: [String: Lookup]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
        lookups = (try? JSONDecoder().decode([String: Lookup].self, from: Data(contentsOf: Self.lookupsFile))) ?? [:]
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Archivo local con la imagen, descargándola si hace falta. `nil` si no se encontró.
    func localFile(for card: CardRef, size: CardImageSize) async -> URL? {
        let file = Self.cacheDirectory.appendingPathComponent("\(Self.safe(card.key))_\(size.rawValue).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if let failed = lookups[card.key]?.failedAt, Date().timeIntervalSince(failed) < Self.retryAfter { return nil }
        let taskKey = file.lastPathComponent
        if let task = inFlight[taskKey] { return await task.value }
        let task = Task { await self.fetch(card, size: size, to: file) }
        inFlight[taskKey] = task
        let result = await task.value
        inFlight[taskKey] = nil
        return result
    }

    /// Borra las imágenes descargadas y lo que se recordaba de la API.
    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        lookups = [:]
        saveLookups()
    }

    private func fetch(_ card: CardRef, size: CardImageSize, to file: URL) async -> URL? {
        await acquire()
        defer { release() }

        if let url = limitlessURL(card, size: size), await download(url, to: file) {
            return file
        }
        let known = lookups[card.key]
        let remote = size == .small ? known?.small : known?.large
        if let remote, await download(remote, to: file) { return file }

        if let found = await searchAPI(card) {
            lookups[card.key] = Lookup(small: found.small, large: found.large)
            saveLookups()
            if await download(size == .small ? found.small : found.large, to: file) { return file }
        }
        lookups[card.key] = Lookup(failedAt: Date())
        saveLookups()
        return nil
    }

    private func limitlessURL(_ card: CardRef, size: CardImageSize) -> URL? {
        guard let set = card.setCode, let number = card.paddedNumber else { return nil }
        let suffix = size == .small ? "SM" : "LG"
        return URL(string: "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/\(set)/\(set)_\(number)_R_EN_\(suffix).png")
    }

    private struct APIResponse: Decodable {
        struct Card: Decodable {
            struct Images: Decodable { let small: URL; let large: URL }
            let images: Images
        }
        let data: [Card]
    }

    /// pokemontcg.io: primero por set y número; si no, por nombre (la impresión más reciente).
    private func searchAPI(_ card: CardRef) async -> (small: URL, large: URL)? {
        var queries: [String] = []
        if let set = card.setCode, let number = card.number {
            let plain = number.drop { $0 == "0" }
            queries.append("set.ptcgoCode:\(set) number:\(plain.isEmpty ? "0" : plain)")
        }
        queries.append("name:\"\(card.searchName)\"")
        for query in queries {
            var components = URLComponents(string: "https://api.pokemontcg.io/v2/cards")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "select", value: "images"),
                URLQueryItem(name: "orderBy", value: "-set.releaseDate"),
                URLQueryItem(name: "pageSize", value: "1"),
            ]
            guard let (data, response) = try? await session.data(from: components.url!),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let card = try? JSONDecoder().decode(APIResponse.self, from: data).data.first else { continue }
            return (card.images.small, card.images.large)
        }
        return nil
    }

    private func download(_ url: URL, to file: URL) async -> Bool {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    private func saveLookups() {
        guard let data = try? JSONEncoder().encode(lookups) else { return }
        try? FileManager.default.createDirectory(at: Self.lookupsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.lookupsFile, options: .atomic)
    }

    private func acquire() async {
        if running < Self.maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    private static func safe(_ key: String) -> String {
        key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.map(String.init).joined()
    }
}

/// Imágenes ya leídas de disco, para no decodificarlas otra vez al hacer scroll.
@MainActor
enum CardImageMemory {
    private static let cache = NSCache<NSURL, PlatformImage>()

    static func image(at url: URL) -> PlatformImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = PlatformImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Imagen de una carta con su estado de carga y una carta de relleno si no aparece.
struct CardImage: View {
    let entry: CardEntry
    var size: CardImageSize = .small
    @State private var image: PlatformImage?
    @State private var failed = false

    static let aspectRatio: CGFloat = 63.0 / 88.0

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else if failed {
                CardPlaceholder(entry: entry)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: size == .small ? 6 : 14))
        .task(id: "\(entry.cardKey)|\(size.rawValue)") {
            failed = false
            if let file = await CardImageService.shared.localFile(for: CardRef(entry), size: size),
               let loaded = CardImageMemory.image(at: file) {
                image = loaded
            } else {
                image = nil
                failed = true
            }
        }
    }
}

/// Se muestra cuando no hay imagen: así la lista siempre se ve completa.
struct CardPlaceholder: View {
    let entry: CardEntry

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [entry.section.color.opacity(0.55), entry.section.color.opacity(0.25)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: entry.section.symbol)
                        .font(.title2)
                    Text(entry.name)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if let set = entry.setCode, let number = entry.number {
                        Text("\(set) \(number)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
    }
}

extension DeckSection {
    var color: Color {
        switch self {
        case .pokemon: .red
        case .trainer: .blue
        case .energy: .orange
        }
    }

    var symbol: String {
        switch self {
        case .pokemon: "flame"
        case .trainer: "person.fill"
        case .energy: "bolt.fill"
        }
    }
}
