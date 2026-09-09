import Foundation

/// Una especie de la Pokédex #1-#251, tal y como viene en `Resources/pokedex.json`.
public struct Pokemon: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let localizedName: String
    public let slug: String
    public let generation: Int
    public let types: [String]
    public let baseStatTotal: Int
    public let captureRate: Int
    public let rarity: Rarity
    /// Distancia a la forma base dentro de su cadena evolutiva (0, 1 o 2).
    public let stage: Int
    public let baseFormID: Int
    /// Evoluciones directas. Puede haber varias (Eevee, Gloom, Slowpoke, Tyrogue).
    public let evolvesInto: [Int]
    public let isLegendary: Bool
    public let isStarter: Bool

    public var isBaseForm: Bool { stage == 0 }

    /// Región de origen. Se dice en la UI en vez de la generación porque
    /// "Gen 2" se lee como "región 2" y en este juego es al revés: la región 1
    /// es **Johto**, cuyos Pokémon son los de Gen 2 (#152-251), y la 2 es
    /// **Kanto**, que son los de Gen 1.
    public var homeRegion: String { generation == 1 ? "Kanto" : "Johto" }
    /// Etiqueta completa, para cuando el número de Pokédex también importa.
    public var regionLabel: String { "\(homeRegion) · Gen \(generation)" }
    public var displayTypes: String { types.map(\.capitalized).joined(separator: " / ") }

    /// Rango de entrenador que hace falta para que aparezca en libertad.
    public var requiredRankLabel: String {
        let rank = rarity.requiredRank
        return rank == .novato ? "desde el principio" : "\(rank.label) (\(rank.requiredMedals) medallas)"
    }
}

public struct PokedexFile: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let source: String
    public let pokemon: [Pokemon]
}
