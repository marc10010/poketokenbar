import Foundation

/// Qué le pasa a un jefe cuando le caen tokens encima. Los tres combates de
/// jefe (gimnasio, hito y liga) resolvían esto con la misma secuencia copiada
/// tres veces; lo que cambia de verdad entre ellos es qué hacen **cuando cae**,
/// y eso se queda en cada mecánica.
public enum BossHit: Equatable, Sendable {
    /// El cruce de tipos no basta: los tokens se gastan y el HP no se mueve.
    case blocked
    /// Aguantó: le queda este HP.
    case survived(hp: Int)
    /// Cayó, y le sobraron tokens al jugador después de gastar `spent`.
    case fell(spent: Int)
}

/// Aritmética del combate de gimnasio: **no se pierde, se bloquea**.
///
/// Un líder absorbe daño y solo le hace mella lo que pase de su umbral, así que
/// con un cruce de tipos insuficiente el progreso es cero por muchos tokens que
/// se le tiren. La medalla se gana eligiendo bien el compañero, no esperando.
public struct GymCombat {
    /// Lo que suma cada etapa evolutiva al multiplicador, antes de restar la
    /// absorción: criar a un Pokémon tiene que servir para algo. Solo aplica en
    /// gimnasios; en los salvajes cambiaría la economía de todo el juego.
    public static let stageBonusPerStage = 0.25

    public init() {}

    public func stageBonus(for stage: EvolutionStage) -> Double {
        Double(stage.rawValue) * Self.stageBonusPerStage
    }

    /// HP que quita cada token contra este líder. Cero significa bloqueado.
    public func damagePerToken(matchup: Double, absorption: Double, stage: EvolutionStage = .base) -> Double {
        max(0, matchup + stageBonus(for: stage) - absorption)
    }

    public func isBlocked(matchup: Double, absorption: Double, stage: EvolutionStage = .base) -> Bool {
        damagePerToken(matchup: matchup, absorption: absorption, stage: stage) <= 0
    }

    /// Daño de un evento entero, redondeado a HP enteros. Si está bloqueado son
    /// 0 HP: los tokens se gastan igual (cuentan para el ledger y para la
    /// evolución del compañero) pero el líder no se mueve.
    public func damage(tokens: Int, matchup: Double, absorption: Double, stage: EvolutionStage = .base) -> Int {
        guard tokens > 0 else { return 0 }
        let rate = damagePerToken(matchup: matchup, absorption: absorption, stage: stage)
        guard rate > 0 else { return 0 }
        return max(1, Int((Double(tokens) * rate).rounded()))
    }

    /// Aplica un evento entero contra un jefe con `hp` puntos de vida.
    ///
    /// Es la secuencia que estaba triplicada: mirar si está bloqueado, calcular
    /// lo que hace falta para tumbarlo, y si no llega, quitarle lo que se pueda.
    public func apply(
        tokens: Int,
        toHP hp: Int,
        matchup: Double,
        absorption: Double,
        stage: EvolutionStage = .base
    ) -> BossHit {
        guard damagePerToken(matchup: matchup, absorption: absorption, stage: stage) > 0 else { return .blocked }
        let needed = tokensNeeded(for: hp, matchup: matchup, absorption: absorption, stage: stage) ?? tokens
        guard tokens >= needed else {
            let hit = damage(tokens: tokens, matchup: matchup, absorption: absorption, stage: stage)
            return .survived(hp: hp - min(hp, hit))
        }
        return .fell(spent: needed)
    }

    /// Tokens necesarios para tumbar el HP que queda. `nil` si está bloqueado:
    /// no hay cantidad de tokens que valga.
    public func tokensNeeded(for remainingHP: Int, matchup: Double, absorption: Double, stage: EvolutionStage = .base) -> Int? {
        let rate = damagePerToken(matchup: matchup, absorption: absorption, stage: stage)
        guard rate > 0, remainingHP > 0 else { return remainingHP <= 0 ? 0 : nil }
        return max(1, Int((Double(remainingHP) / rate).rounded(.up)))
    }
}
