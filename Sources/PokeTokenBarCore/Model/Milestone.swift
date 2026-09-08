import Foundation

/// Un hito legendario: un legendario con **sitio y requisito**, en vez de un
/// 2 % invisible en el sorteo. Se afronta cuando el jugador quiere.
///
/// El sitio es una zona del catálogo de zonas, así que el requisito base es
/// "esa zona está abierta" y no hay reglas de desbloqueo duplicadas.
public struct Milestone: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let place: String
    public let zoneID: String
    public let speciesID: Int
    public let region: String
    /// Medallas por encima de las que ya pide la zona. 0 = solo la zona.
    public let extraMedals: Int
    /// Especies en la Pokédex, si el hito lo pide (Mew).
    public let requiredSpecies: Int?
    public let hp: [Int]
    public let absorption: Double

    public var hpRange: ClosedRange<Int> {
        let low = hp.first ?? 1_500_000
        let high = hp.count > 1 ? hp[1] : low
        return low...max(low, high)
    }
}

public struct MilestoneCatalogFile: Codable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let milestones: [Milestone]
}

/// Por qué un hito no está disponible todavía, para poder decirlo en la UI en
/// vez de dejarlo en gris sin explicación.
public enum MilestoneAvailability: Hashable, Sendable {
    case available
    case defeated
    case zoneClosed(String)
    case needsMedals(Int)
    case needsSpecies(Int)
    case busy

    public var isAvailable: Bool { self == .available }

    public var reason: String {
        switch self {
        case .available: return "disponible"
        case .defeated: return "conseguido"
        case .zoneClosed(let zone): return "hay que abrir \(zone)"
        case .needsMedals(let count): return "faltan \(count) medallas"
        case .needsSpecies(let count): return "faltan \(count) especies en la Pokédex"
        case .busy: return "termina el combate en curso"
        }
    }
}

/// Combate de hito en curso, y los ya conseguidos.
public struct MilestoneProgress: Codable, Hashable, Sendable {
    public var defeated: [String] = []
    public var current: ActiveBossBattle?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defeated = try container.decodeIfPresent([String].self, forKey: .defeated) ?? []
        current = try container.decodeIfPresent(ActiveBossBattle.self, forKey: .current)
    }

    public var defeatedIDs: Set<String> { Set(defeated) }

    public mutating func award(_ id: String) {
        guard !defeated.contains(id) else { return }
        defeated.append(id)
    }
}

/// Combate contra un jefe que no es un gimnasio. Misma forma que
/// `ActiveGymBattle`: lo que cambia es la recompensa, no el combate.
public struct ActiveBossBattle: Codable, Hashable, Sendable {
    public let milestoneID: String
    public let maxHP: Int
    public var currentHP: Int
    public var tokensSpent: Int
    public let startedAt: Date

    public init(milestoneID: String, maxHP: Int, currentHP: Int? = nil, tokensSpent: Int = 0, startedAt: Date = Date()) {
        self.milestoneID = milestoneID
        self.maxHP = max(1, maxHP)
        self.currentHP = min(max(0, currentHP ?? maxHP), max(1, maxHP))
        self.tokensSpent = tokensSpent
        self.startedAt = startedAt
    }

    public var isDefeated: Bool { currentHP <= 0 }
    public var hpFraction: Double { Double(currentHP) / Double(maxHP) }
}
