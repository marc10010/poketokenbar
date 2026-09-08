import Foundation

/// Combate de gimnasio en curso. Hay como mucho uno.
public struct ActiveGymBattle: Codable, Hashable, Sendable {
    public let gymID: String
    public let maxHP: Int
    public var currentHP: Int
    /// Tokens gastados desde que se abrió, incluidos los que no hicieron daño
    /// por estar bloqueado: se gastaron de verdad.
    public var tokensSpent: Int
    public let startedAt: Date

    public init(gymID: String, maxHP: Int, currentHP: Int? = nil, tokensSpent: Int = 0, startedAt: Date = Date()) {
        self.gymID = gymID
        self.maxHP = max(1, maxHP)
        self.currentHP = min(max(0, currentHP ?? maxHP), max(1, maxHP))
        self.tokensSpent = tokensSpent
        self.startedAt = startedAt
    }

    public var isDefeated: Bool { currentHP <= 0 }
    public var hpFraction: Double { Double(currentHP) / Double(maxHP) }
}

/// Progreso de gimnasios: medallas conseguidas, contadores del disparador y el
/// combate abierto si lo hay.
public struct GymProgress: Codable, Hashable, Sendable {
    /// Ids en el orden en que se ganaron.
    public var defeated: [String] = []
    /// Tokens y capturas desde que terminó el último gimnasio. Se reinician al
    /// **terminar**, no al empezar: si se reiniciaran al abrirlo, los 500k-1M
    /// tokens del propio combate volverían a llenar el contador y encadenarían
    /// gimnasios sin descanso.
    public var tokensSinceLastGym: Int = 0
    public var capturesSinceLastGym: Int = 0
    public var current: ActiveGymBattle?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defeated = try container.decodeIfPresent([String].self, forKey: .defeated) ?? []
        tokensSinceLastGym = try container.decodeIfPresent(Int.self, forKey: .tokensSinceLastGym) ?? 0
        capturesSinceLastGym = try container.decodeIfPresent(Int.self, forKey: .capturesSinceLastGym) ?? 0
        current = try container.decodeIfPresent(ActiveGymBattle.self, forKey: .current)
    }

    public var defeatedIDs: Set<String> { Set(defeated) }
    public var medals: Int { defeated.count }
    public var rank: TrainerRank { .rank(forMedals: medals) }

    /// El disparador: cualquiera de las dos condiciones basta.
    public func triggerIsMet(extraTokens: Int = 0, extraCaptures: Int = 0) -> Bool {
        tokensSinceLastGym + extraTokens >= GameRules.gymTokenInterval
            || capturesSinceLastGym + extraCaptures >= GameRules.gymCaptureInterval
    }

    public mutating func resetCounters() {
        tokensSinceLastGym = 0
        capturesSinceLastGym = 0
    }

    /// Otorga la medalla una sola vez, por si un evento gigante pasa de sobra
    /// del HP del líder.
    public mutating func award(gymID: String) {
        guard !defeated.contains(gymID) else { return }
        defeated.append(gymID)
    }
}
