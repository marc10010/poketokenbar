import Foundation

/// Un miembro del Alto Mando o un campeón. Es un jefe más: el combate es el
/// mismo que el de un gimnasio, lo que cambia es la recompensa.
public struct LeagueMember: Codable, Hashable, Sendable {
    public let name: String
    public let signatureSpeciesID: Int
    public let order: Int
    public let absorption: Double
    public let hp: [Int]

    public var hpRange: ClosedRange<Int> {
        let low = hp.first ?? 800_000
        let high = hp.count > 1 ? hp[1] : low
        return low...max(low, high)
    }
}

/// Qué abre ganar una liga.
public enum LeagueReward: String, Codable, Hashable, Sendable {
    /// Abre la región de Kanto: sus gimnasios y sus zonas.
    case kanto
    /// Campeón: abre Cueva Celeste y el título.
    case champion

    public var label: String {
        switch self {
        case .kanto: return "Abre la región de Kanto"
        case .champion: return "Campeón · abre Cueva Celeste"
        }
    }

    /// Región de gimnasios que abre, si abre alguna. La usa la UI para decir
    /// qué hay que ganar para poder retar a los gimnasios de esa región.
    public var opensRegion: String? {
        switch self {
        case .kanto: return "kanto"
        case .champion: return nil
        }
    }
}

/// Una liga es un **gauntlet**: sus miembros en cadena y sin salvajes entre
/// medias. Abandonar reinicia la tirada, que es lo que significa un gauntlet.
public struct League: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let place: String
    public let requiredMedals: Int
    public let reward: LeagueReward
    public let members: [LeagueMember]

    public func member(at index: Int) -> LeagueMember? {
        members.indices.contains(index) ? members[index] : nil
    }
}

public struct LeagueCatalogFile: Codable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let leagues: [League]
}

/// Por qué una liga no se puede afrontar todavía.
public enum LeagueAvailability: Hashable, Sendable {
    case available
    case won
    case needsMedals(Int)
    case needsPreviousLeague(String)
    case busy

    public var isAvailable: Bool { self == .available }

    public var reason: String {
        switch self {
        case .available: return "disponible"
        case .won: return "superada"
        case .needsMedals(let count): return "faltan \(count) medallas"
        case .needsPreviousLeague(let name): return "primero \(name)"
        case .busy: return "termina el combate en curso"
        }
    }
}

/// Tirada de liga en curso: qué miembro toca y cómo va.
public struct ActiveLeagueRun: Codable, Hashable, Sendable {
    public let leagueID: String
    public var memberIndex: Int
    public let maxHP: Int
    public var currentHP: Int
    public var tokensSpent: Int
    public let startedAt: Date

    public init(
        leagueID: String,
        memberIndex: Int = 0,
        maxHP: Int,
        currentHP: Int? = nil,
        tokensSpent: Int = 0,
        startedAt: Date = Date()
    ) {
        self.leagueID = leagueID
        self.memberIndex = memberIndex
        self.maxHP = max(1, maxHP)
        self.currentHP = min(max(0, currentHP ?? maxHP), max(1, maxHP))
        self.tokensSpent = tokensSpent
        self.startedAt = startedAt
    }

    public var hpFraction: Double { Double(currentHP) / Double(maxHP) }
}

public struct LeagueProgress: Codable, Hashable, Sendable {
    public var won: [String] = []
    public var current: ActiveLeagueRun?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        won = try container.decodeIfPresent([String].self, forKey: .won) ?? []
        current = try container.decodeIfPresent(ActiveLeagueRun.self, forKey: .current)
    }

    public var wonIDs: Set<String> { Set(won) }

    /// Kanto se abre ganando el Alto Mando de Johto, no acumulando medallas.
    public var kantoOpen: Bool { wonIDs.contains("johto") }
    public var isChampion: Bool { wonIDs.contains("kanto") }

    public mutating func award(_ id: String) {
        guard !won.contains(id) else { return }
        won.append(id)
    }
}
