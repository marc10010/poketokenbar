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
        /// Los animados son los GIF de Gen 5. Cubren del #1 al #649, así que
        /// los 251 están, pero se piden aparte: en una rejilla de 251 celdas
        /// animar todo saldría carísimo.
        public var animated: Bool = false
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
    public func image(speciesID: Int, shiny: Bool, animated: Bool = false) -> NSImage? {
        let key = Key(speciesID: speciesID, shiny: shiny, animated: animated)
        if let cached = images[key] { return cached }
        if let disk = loadFromDisk(key) {
            images[key] = disk
            return disk
        }
        download(key)
        return nil
    }

    /// Fotogramas de un sprite ya cargado. Sirve para comprobar de verdad que
    /// un animado anima en vez de fiarse de que la URL exista.
    public func frameCount(speciesID: Int, shiny: Bool, animated: Bool) -> Int? {
        let key = Key(speciesID: speciesID, shiny: shiny, animated: animated)
        guard let image = images[key] ?? loadFromDisk(key) else { return nil }
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let frames = bitmap.value(forProperty: .frameCount) as? Int
        else { return 1 }
        return frames
    }

    private func fileURL(_ key: Key) -> URL {
        let suffix = key.shiny ? "-shiny" : ""
        let name = "\(key.speciesID)\(suffix)"
        return cacheDirectory.appendingPathComponent(key.animated ? "\(name)-anim.gif" : "\(name).png")
    }

    private func remoteURL(_ key: Key) -> URL? {
        let variant = key.shiny ? "shiny/" : ""
        let root = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
        if key.animated {
            return URL(string: "\(root)/versions/generation-v/black-white/animated/\(variant)\(key.speciesID).gif")
        }
        return URL(string: "\(root)/\(variant)\(key.speciesID).png")
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
            else {
                // Sin animado para esa especie, el estático sirve igual.
                if key.animated {
                    await MainActor.run { _ = self.image(speciesID: key.speciesID, shiny: key.shiny) }
                }
                return
            }
            try? data.write(to: self.fileURL(key), options: .atomic)
            await MainActor.run { self.images[key] = image }
        }
    }
}
