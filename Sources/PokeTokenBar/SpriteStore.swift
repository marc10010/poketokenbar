import AppKit
import Combine
import PokeTokenBarCore

/// Sprites retro de PokeAPI, con caché en disco. La primera carga baja el PNG;
/// después todo sale de `~/Library/Caches/PokeTokenBar/sprites`.
@MainActor
public final class SpriteStore: ObservableObject {
    public struct Key: Hashable {
        public let speciesID: Int
        public let shiny: Bool
    }

    @Published private(set) var images: [Key: NSImage] = [:]

    private let cacheDirectory: URL
    private let session: URLSession
    private var inFlight: Set<Key> = []

    public init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("PokeTokenBar/sprites")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        session = URLSession(configuration: configuration)
    }

    /// Devuelve el sprite si ya está disponible y, si no, lo pide en background.
    public func image(speciesID: Int, shiny: Bool) -> NSImage? {
        let key = Key(speciesID: speciesID, shiny: shiny)
        if let cached = images[key] { return cached }
        if let disk = loadFromDisk(key) {
            images[key] = disk
            return disk
        }
        download(key)
        return nil
    }

    private func fileURL(_ key: Key) -> URL {
        cacheDirectory.appendingPathComponent("\(key.speciesID)\(key.shiny ? "-shiny" : "").png")
    }

    private func remoteURL(_ key: Key) -> URL? {
        let variant = key.shiny ? "shiny/" : ""
        return URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(variant)\(key.speciesID).png")
    }

    private func loadFromDisk(_ key: Key) -> NSImage? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return NSImage(data: data)
    }

    private func download(_ key: Key) {
        guard !inFlight.contains(key), let url = remoteURL(key) else { return }
        inFlight.insert(key)
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight.remove(key) } }
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data)
            else { return }
            try? data.write(to: self.fileURL(key), options: .atomic)
            await MainActor.run { self.images[key] = image }
        }
    }
}
