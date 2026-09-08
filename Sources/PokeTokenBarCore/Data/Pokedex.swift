import Foundation

/// Índice en memoria de la Pokédex embebida. Se carga una vez.
public final class Pokedex: @unchecked Sendable {
    public static let shared: Pokedex = {
        do {
            return try Pokedex(bundle: .module)
        } catch {
            fatalError("pokedex.json no se pudo cargar: \(error)")
        }
    }()

    public let all: [Pokemon]
    private let byID: [Int: Pokemon]
    private let byRarity: [Rarity: [Pokemon]]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "pokedex", withExtension: "json") else {
            throw PokedexError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(PokedexFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw PokedexError.unsupportedSchema(decoded.schemaVersion) }
        all = decoded.pokemon.sorted { $0.id < $1.id }
        byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        byRarity = Dictionary(grouping: all, by: \.rarity)
    }

    public subscript(id: Int) -> Pokemon? { byID[id] }

    public func require(_ id: Int) -> Pokemon {
        guard let mon = byID[id] else { fatalError("especie #\(id) fuera de la Pokédex #1-#251") }
        return mon
    }

    /// Candidatos a rival de un tier. Solo formas base: un rival salvaje
    /// arranca su línea evolutiva, y así la caja PC guarda cadenas completas.
    public func spawnCandidates(rarity: Rarity) -> [Pokemon] {
        let pool = (byRarity[rarity] ?? []).filter(\.isBaseForm)
        return pool.isEmpty ? (byRarity[rarity] ?? []) : pool
    }

    public var starters: [Pokemon] { all.filter { $0.isStarter && $0.isBaseForm } }

    public enum PokedexError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "pokedex.json no está en el bundle"
            case .unsupportedSchema(let v): return "schemaVersion \(v) no soportada"
            }
        }
    }
}
