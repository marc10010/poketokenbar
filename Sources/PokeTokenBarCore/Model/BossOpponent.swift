import Foundation

/// Lo único que el combate necesita saber de un jefe: contra qué especie se
/// mide el cruce de tipos y cuánto daño absorbe.
///
/// Existe porque las tres mecánicas de jefe —líder de gimnasio, miembro del
/// Alto Mando y legendario de hito— llegaron una detrás de otra y cada una
/// copió las funciones de la anterior: había tres `matchup`, tres
/// `damagePerToken` y tres `isBlocked` idénticos salvo en qué campo leían. Un
/// arreglo en la fórmula había que hacerlo tres veces, y el aviso de "no le
/// haces nada, cambia a X" solo llegó a existir en los gimnasios.
///
/// A propósito **no** incluye nombre, sitio ni HP: eso lo pinta cada mecánica
/// como quiera, y meterlo aquí sería obligar a las tres a parecerse en cosas
/// en las que no se parecen.
public protocol BossOpponent: Sendable {
    /// Especie contra la que se calcula el cruce de tipos.
    var opponentSpeciesID: Int { get }
    /// Daño por token que se come antes de tocarle el HP.
    var absorption: Double { get }
}

extension Gym: BossOpponent {
    public var opponentSpeciesID: Int { signatureSpeciesID }
}

extension LeagueMember: BossOpponent {
    public var opponentSpeciesID: Int { signatureSpeciesID }
}

extension Milestone: BossOpponent {
    public var opponentSpeciesID: Int { speciesID }
}
