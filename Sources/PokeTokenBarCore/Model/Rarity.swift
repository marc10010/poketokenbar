import Foundation

/// Tiers de aparición. La rareza dice **cada cuánto** sale una especie dentro
/// de su zona; lo que aguanta lo dice la zona.
public enum Rarity: String, Codable, CaseIterable, Sendable {
    case common
    case uncommon
    case rare
    case legendary

    /// Peso dentro de la zona. Más plano que el 60/28/10 de cuando el sorteo
    /// era global: con la zona como bombo único, un reparto muy sesgado hace
    /// eternas las cacerías concretas, y uno plano del todo deja la rareza sin
    /// significado.
    public var spawnWeight: Double {
        switch self {
        case .common: return 0.45
        case .uncommon: return 0.33
        case .rare: return 0.22
        case .legendary: return 0
        }
    }

    /// HP de los jefes de este tier. Los salvajes ya no lo usan: su vida sale
    /// de la profundidad de la zona.
    public var hpRange: ClosedRange<Int> {
        switch self {
        case .common: return 10_000...50_000
        case .uncommon: return 75_000...200_000
        case .rare: return 250_000...600_000
        case .legendary: return 1_500_000...4_000_000
        }
    }

    /// Si aparece en libertad. Los legendarios no: son hitos con sitio y
    /// requisito, y dejarlos también en el sorteo los abarataría.
    public var spawnsInTheWild: Bool { self != .legendary }

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

    /// Orden para listar: primero lo difícil de conseguir.
    public var sortIndex: Int {
        switch self {
        case .legendary: return 0
        case .rare: return 1
        case .uncommon: return 2
        case .common: return 3
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
    /// Especies de la región anterior que hay que tener registradas para que
    /// salga el barco a la siguiente.
    ///
    /// El equivalente al Dock Pass de PokéClicker, que allí se compra con
    /// moneda: aquí no hay monedas, así que el peaje es la Pokédex. 70 de las
    /// 151 de Kanto son las 66 que se encuentran antes de Johto más criar
    /// cuatro, unos 800.000 tokens: obliga a recorrer la región sin ser un
    /// muro.
    public static let regionTransferSpecies = 70

    /// Inicial de cada región. No se elige: **cada región regala el suyo al
    /// llegar**, como el profesor de su pueblo. Elegir entre seis no aportaba
    /// una decisión —cualquiera sirve igual, porque lo que decide un combate es
    /// el cruce de tipos del rival de turno— y además ofrecía los tres de Johto
    /// para empezar en Kanto, que es la región 1.
    public static let starterByRegion = ["kanto": 4, "johto": 155]   // Charmander · Cyndaquil

    /// 1 token = 1 punto de daño.
    public static let damagePerToken = 1
    public static let shinyProbability = 0.01
    /// Umbrales de evolución sobre el histórico acumulado de tokens.
    public static let stageOneThreshold = 200_001
    public static let stageTwoThreshold = 1_000_001
    /// Cuántos IDs de evento guardamos para idempotencia entre reinicios.
    public static let processedEventWindow = 20_000
    /// Techo del bonus por Pokédex completada. Con las 251, +3,0 al
    /// multiplicador contra salvajes.
    ///
    /// Sube con la curva de HP por zona: es la mitad de la carrera. Si el HP
    /// se multiplica por seis de la primera zona a la última y el daño solo
    /// por dos, volver a una zona vieja nunca se notaría barato. Solo cuenta
    /// contra salvajes, así que no toca el equilibrio de los jefes.
    public static let collectionBonusCap = 3.0

    /// Vida de un salvaje en la zona menos profunda. Las demás salen de aquí
    /// multiplicando por `zoneHPGrowth` una vez por escalón.
    public static let zoneBaseHP = 60_000.0
    /// Cuánto pesa más cada zona que la anterior. Con 32 zonas, ×6 de punta a
    /// punta. PokéClicker usa ~×1,27 por ruta porque allí el ataque crece
    /// miles de veces; aquí el daño crece ×4 como mucho.
    public static let zoneHPGrowth = 1.0595
    /// Límites del multiplicador de sprites: por debajo no se distingue nada y
    /// por encima el popover se va de la pantalla.
    public static let minimumSpriteScale = 0.75
    public static let maximumSpriteScale = 2.0
    /// Cuánto dura la celebración de una medalla antes de volver al combate.
    public static let medalCelebrationSeconds: TimeInterval = 12
    /// Disparador de gimnasio: basta con cumplir una de las dos.
    public static let gymTokenInterval = 300_000
    public static let gymCaptureInterval = 10
    /// Suelo del multiplicador de tipos: una inmunidad (Normal contra Fantasma)
    /// dejaría el combate atascado y los tokens sin efecto, así que pega igual
    /// pero flojísimo.
    public static let minimumDamageMultiplier = 0.25
    public static let maximumDamageMultiplier = 4.0
}
