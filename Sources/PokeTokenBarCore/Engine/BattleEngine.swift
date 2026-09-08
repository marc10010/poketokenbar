import Foundation

/// Qué pasó al aplicar un evento de tokens.
public struct BattleResult: Equatable, Sendable {
    public var damageApplied: Int = 0
    public var captures: [CapturedPokemon] = []
    public var encounter: WildEncounter?
}

/// Aplica daño al rival y encadena capturas. El daño sobrante de una captura
/// se arrastra al rival siguiente: así un evento grande no se pierde y un
/// combate nunca "come" tokens sin efecto.
public struct BattleEngine {
    private let pokedex: Pokedex
    private let spawner: SpawnService

    public init(pokedex: Pokedex = .shared, spawner: SpawnService? = nil) {
        self.pokedex = pokedex
        self.spawner = spawner ?? SpawnService(pokedex: pokedex)
    }

    public func freshEncounter<R: RandomProvider>(totalTokens: Int, using rng: inout R, now: Date = Date()) -> WildEncounter {
        spawner.spawn(totalTokens: totalTokens, using: &rng, now: now)
    }

    /// - Parameters:
    ///   - damage: tokens del evento (1 token = 1 HP).
    ///   - totalTokensAfter: histórico del jugador YA incluyendo este evento,
    ///     que es lo que abre los tiers raro/legendario para el siguiente rival.
    public func apply<R: RandomProvider>(
        damage: Int,
        to encounter: WildEncounter?,
        totalTokensAfter: Int,
        using rng: inout R,
        now: Date = Date()
    ) -> BattleResult {
        var result = BattleResult()
        var current = encounter ?? freshEncounter(totalTokens: totalTokensAfter, using: &rng, now: now)
        var remaining = max(0, damage) * GameRules.damagePerToken

        while remaining > 0 {
            let hit = min(remaining, current.currentHP)
            current.currentHP -= hit
            remaining -= hit
            result.damageApplied += hit

            guard current.isFainted else { break }
            result.captures.append(
                CapturedPokemon(
                    speciesID: current.speciesID,
                    isShiny: current.isShiny,
                    capturedAt: now,
                    capturedAtTotalTokens: totalTokensAfter
                )
            )
            current = freshEncounter(totalTokens: totalTokensAfter, using: &rng, now: now)
        }

        result.encounter = current
        return result
    }
}
