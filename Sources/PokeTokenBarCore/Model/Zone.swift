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
    public var requiresKanto: Bool { region == "kanto" }
    public var requiresChampion: Bool { champion == true }

    /// Orden en que se van abriendo: primero la región 1 por medallas, luego
    /// las de Kanto y al final las que piden ser Campeón. Es el orden en que
    /// el jugador las ve aparecer, y por tanto el orden en que quiere leerlas.
    public var unlockOrder: (Int, Int) {
        let phase = requiresChampion ? 2 : (requiresKanto ? 1 : 0)
        return (phase, requiredMedals)
    }

    public func label(kantoOpen: Bool) -> String {
        if requiresChampion { return "tras vencer a Red" }
        var parts: [String] = []
        if requiresKanto, !kantoOpen { parts.append("abrir Kanto") }
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
    public let kantoOpen: Bool
    public let isChampion: Bool

    public init(medals: Int, kantoOpen: Bool, isChampion: Bool) {
        self.medals = medals
        self.kantoOpen = kantoOpen
        self.isChampion = isChampion
    }

    public func opens(_ zone: Zone) -> Bool {
        if zone.unlock.requiresChampion { return isChampion }
        if zone.unlock.requiresKanto, !kantoOpen { return false }
        return medals >= zone.unlock.requiredMedals
    }
}
