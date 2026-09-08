import Foundation

/// Tiers de aparición. Cada tier define su probabilidad, su rango de HP y el
/// gate de tokens globales que el jugador debe superar para que aparezca.
public enum Rarity: String, Codable, CaseIterable, Sendable {
    case common
    case uncommon
    case rare
    case legendary

    public var spawnWeight: Double {
        switch self {
        case .common: return 0.60
        case .uncommon: return 0.28
        case .rare: return 0.10
        case .legendary: return 0.02
        }
    }

    public var hpRange: ClosedRange<Int> {
        switch self {
        case .common: return 10_000...50_000
        case .uncommon: return 75_000...200_000
        case .rare: return 250_000...600_000
        case .legendary: return 1_500_000...4_000_000
        }
    }

    /// Rango de entrenador que abre el tier: las medallas son el requisito,
    /// no el tiempo.
    public var requiredRank: TrainerRank {
        switch self {
        case .common, .uncommon: return .novato
        case .rare: return .entrenador
        case .legendary: return .ace
        }
    }

    public var label: String {
        switch self {
        case .common: return "Común"
        case .uncommon: return "Poco común"
        case .rare: return "Raro"
        case .legendary: return "Legendario"
        }
    }

    public var badge: String {
        switch self {
        case .common: return "●"
        case .uncommon: return "◆"
        case .rare: return "★"
        case .legendary: return "✦"
        }
    }
}

public enum GameRules {
    /// 1 token = 1 punto de daño.
    public static let damagePerToken = 1
    public static let shinyProbability = 0.01
    /// Umbrales de evolución sobre el histórico acumulado de tokens.
    public static let stageOneThreshold = 200_001
    public static let stageTwoThreshold = 1_000_001
    /// Cuántos IDs de evento guardamos para idempotencia entre reinicios.
    public static let processedEventWindow = 20_000
    /// Disparador de gimnasio: basta con cumplir una de las dos.
    public static let gymTokenInterval = 300_000
    public static let gymCaptureInterval = 10
    /// Suelo del multiplicador de tipos: una inmunidad (Normal contra Fantasma)
    /// dejaría el combate atascado y los tokens sin efecto, así que pega igual
    /// pero flojísimo.
    public static let minimumDamageMultiplier = 0.25
    public static let maximumDamageMultiplier = 4.0
}
