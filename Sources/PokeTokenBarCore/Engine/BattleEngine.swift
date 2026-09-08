import Foundation

/// Qué pasó al aplicar un evento de tokens.
public struct BattleResult: Equatable, Sendable {
    /// HP quitados, que con multiplicador de tipos ya no coincide con tokens.
    public var damageApplied: Int = 0
    public var tokensSpent: Int = 0
    /// Salvajes que han caído. Quedárselos o no es decisión de la colección,
    /// no del combate: el motor solo dice quién cayó.
    public var defeated: [WildEncounter] = []
    public var encounter: WildEncounter?
    /// Tokens que quedaron sin gastar porque una captura abre gimnasio: el
    /// rival siguiente lo pone el gimnasio, no el motor.
    public var remainingTokens: Int = 0
    public var stoppedForGym = false
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

    public func freshEncounter<R: RandomProvider>(rank: TrainerRank, using rng: inout R, now: Date = Date()) -> WildEncounter {
        spawner.spawn(rank: rank, using: &rng, now: now)
    }

    /// - Parameters:
    ///   - damage: tokens del evento. 1 token = 1 HP salvo multiplicador de tipos.
    ///   - totalTokensAfter: histórico del jugador YA incluyendo este evento,
    ///     que es lo que abre los tiers raro/legendario para el siguiente rival.
    ///   - multiplier: se pide por rival, no una vez: si una captura hace
    ///     aparecer otro de tipo distinto, los tokens que sobran se escalan con
    ///     el multiplicador nuevo.
    ///   - openGymAfterCapture: se consulta tras cada captura con el número de
    ///     capturas hechas en esta llamada. Si dice sí, el motor para y devuelve
    ///     los tokens que sobran en vez de sortear otro salvaje: ese hueco lo
    ///     ocupa el líder de gimnasio.
    public func apply<R: RandomProvider>(
        damage: Int,
        to encounter: WildEncounter?,
        totalTokensAfter: Int,
        rank: TrainerRank = .campeon,
        multiplier: (WildEncounter) -> Double = { _ in 1 },
        openGymAfterCapture: (Int) -> Bool = { _ in false },
        using rng: inout R,
        now: Date = Date()
    ) -> BattleResult {
        var result = BattleResult()
        var current = encounter ?? freshEncounter(rank: rank, using: &rng, now: now)
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

            result.defeated.append(current)
            if openGymAfterCapture(result.defeated.count) {
                result.stoppedForGym = true
                result.remainingTokens = remainingTokens
                result.encounter = nil
                return result
            }
            current = freshEncounter(rank: rank, using: &rng, now: now)
        }

        result.encounter = current
        return result
    }
}
