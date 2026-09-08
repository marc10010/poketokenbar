import Foundation

/// Un gimnasio del catálogo. `type` es solo el tema del gimnasio: el daño se
/// calcula contra los **tipos reales del Pokémon estrella**, así que a Onix
/// (roca/tierra) el agua le entra ×4 y no ×2.
public struct Gym: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let leader: String
    public let city: String
    public let region: String
    public let type: String
    public let signatureSpeciesID: Int
    public let medal: String
    public let order: Int
    /// Rango de HP; el valor concreto se sortea al abrir el gimnasio.
    public let hp: [Int]
    /// Umbral de daño: solo hace mella lo que pase de aquí (ver `GymCombat`).
    public let absorption: Double

    public var hpRange: ClosedRange<Int> {
        let low = hp.first ?? 500_000
        let high = hp.count > 1 ? hp[1] : low
        return low...max(low, high)
    }
}

public struct GymCatalogFile: Codable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let gyms: [Gym]
}

/// Rango de entrenador. Las medallas son el único requisito, y el rango es lo
/// que abre los tiers de aparición: acumular tokens ya no basta.
public enum TrainerRank: Int, CaseIterable, Comparable, Sendable {
    case novato = 0
    case entrenador = 1
    case veterano = 2
    case ace = 3
    case campeon = 4

    public static func < (lhs: TrainerRank, rhs: TrainerRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Medallas necesarias para alcanzarlo.
    public var requiredMedals: Int {
        switch self {
        case .novato: return 0
        case .entrenador: return 2
        case .veterano: return 5
        case .ace: return 8
        case .campeon: return 16
        }
    }

    public var label: String {
        switch self {
        case .novato: return "Novato"
        case .entrenador: return "Entrenador"
        case .veterano: return "Veterano"
        case .ace: return "As"
        case .campeon: return "Campeón"
        }
    }

    public static func rank(forMedals medals: Int) -> TrainerRank {
        allCases.last { medals >= $0.requiredMedals } ?? .novato
    }

    /// Siguiente rango y cuántas medallas faltan. `nil` si ya es el máximo.
    public func next(medals: Int) -> (rank: TrainerRank, missing: Int)? {
        guard let next = TrainerRank(rawValue: rawValue + 1) else { return nil }
        return (next, max(0, next.requiredMedals - medals))
    }
}
