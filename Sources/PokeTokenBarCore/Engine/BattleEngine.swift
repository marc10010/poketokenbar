import Foundation

/// Qué pasó al aplicar un evento de tokens.
public struct BattleResult: Equatable, Sendable {
    /// HP quitados, que con multiplicador de tipos ya no coincide con tokens.
    public var damageApplied: Int = 0
    public var tokensSpent: Int = 0
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
    ///   - damage: tokens del evento. 1 token = 1 HP salvo multiplicador de tipos.
    ///   - totalTokensAfter: histórico del jugador YA incluyendo este evento,
    ///     que es lo que abre los tiers raro/legendario para el siguiente rival.
    ///   - multiplier: se pide por rival, no una vez: si una captura hace
    ///     aparecer otro de tipo distinto, los tokens que sobran se escalan con
    ///     el multiplicador nuevo.
    public func apply<R: RandomProvider>(
        damage: Int,
        to encounter: WildEncounter?,
        totalTokensAfter: Int,
        multiplier: (WildEncounter) -> Double = { _ in 1 },
        using rng: inout R,
        now: Date = Date()
    ) -> BattleResult {
        var result = BattleResult()
        var current = encounter ?? freshEncounter(totalTokens: totalTokensAfter, using: &rng, now: now)
        var remainingTokens = max(0, damage)

        while remainingTokens > 0 {
            let factor = max(GameRules.minimumDamageMultiplier, multiplier(current))
            let capacity = Double(remainingTokens) * factor

            guard capacity >= Double(current.currentHP) else {
                // No llega para tumbarlo: todo el evento va a este rival.
                let hit = min(current.currentHP, max(1, Int((Double(remainingTokens) * factor).rounded())))
                current.currentHP -= hit
                result.damageApplied += hit
                result.tokensSpent += remainingTokens
                remainingTokens = 0
                break
            }

            // Cae: solo se gastan los tokens que hacían falta, el resto sigue.
            let needed = max(1, Int((Double(current.currentHP) / factor).rounded(.up)))
            let spent = min(remainingTokens, needed)
            result.damageApplied += current.currentHP
            result.tokensSpent += spent
            remainingTokens -= spent
            current.currentHP = 0

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
