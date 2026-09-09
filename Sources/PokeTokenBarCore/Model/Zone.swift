import Foundation

/// Requisito de apertura de una zona.
public struct ZoneUnlock: Codable, Hashable, Sendable {
    public var medals: Int?
    public var region: String?
    public var champion: Bool?

    public init(medals: Int? = nil, region: String? = nil, champion: Bool? = nil) {
        self.medals = medals
        self.region = region
        self.champion = champion
    }

    public var requiredMedals: Int { medals ?? 0 }
    /// Región que hay que haber abierto, si la zona está en la segunda o
    /// posteriores. Antes esto era `requiresKanto`, con el nombre de la región
    /// metido en el código: dejó de valer al invertir el orden de juego.
    public var requiredRegion: String? { region }
    public var requiresChampion: Bool { champion == true }

    /// Orden en que se van abriendo: primero la región 1 por medallas, luego
    /// las que piden otra región, y al final las que piden ser Campeón. Es el
    /// orden en que el jugador las ve aparecer.
    public var unlockOrder: (Int, Int) {
        let phase = requiresChampion ? 2 : (requiredRegion != nil ? 1 : 0)
        return (phase, requiredMedals)
    }

    public func label(openRegions: Set<String>) -> String {
        if requiresChampion { return "tras el combate final" }
        var parts: [String] = []
        if let requiredRegion, !openRegions.contains(requiredRegion) {
            parts.append("abrir \(requiredRegion.capitalized)")
        }
        if requiredMedals > 0 { parts.append("\(requiredMedals) medallas") }
        return parts.isEmpty ? "desde el principio" : parts.joined(separator: " y ")
    }
}

/// Una zona de caza: **abre especies**, no sesga probabilidades. Un Pokémon
/// solo puede aparecer si alguna de sus zonas está abierta.
public struct Zone: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let region: String
    public let unlock: ZoneUnlock
    public let species: [Int]

    public var speciesSet: Set<Int> { Set(species) }
}

public struct ZoneCatalogFile: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let source: String
    public let note: String
    public let zones: [Zone]
    /// Especies sin encuentro salvaje en Gen 1/2. Casi todas son formas
    /// evolucionadas, que aquí se consiguen evolucionando.
    public let unassigned: [Int]
}

/// Estado de progreso que decide qué zonas están abiertas.
public struct ZoneAccess: Hashable, Sendable {
    public let medals: Int
    /// Regiones abiertas. Era un `kantoOpen: Bool` cuando Kanto era la única
    /// región que se podía abrir; con el orden de juego invertido —y con
    /// cualquier región nueva— hace falta el conjunto.
    public let openRegions: Set<String>
    public let isChampion: Bool

    public init(medals: Int, openRegions: Set<String> = [], isChampion: Bool = false) {
        self.medals = medals
        self.openRegions = openRegions
        self.isChampion = isChampion
    }

    public func opens(_ zone: Zone) -> Bool {
        if zone.unlock.requiresChampion { return isChampion }
        if let required = zone.unlock.requiredRegion, !openRegions.contains(required) { return false }
        return medals >= zone.unlock.requiredMedals
    }
}
