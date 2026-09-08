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
    public var displayTypes: String { types.map(\.capitalized).joined(separator: " / ") }
}

public struct PokedexFile: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let source: String
    public let pokemon: [Pokemon]
}
