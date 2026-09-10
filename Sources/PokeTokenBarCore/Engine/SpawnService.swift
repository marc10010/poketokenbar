import Foundation

/// Sortea rivales dentro de la zona en la que estás: primero el tier con los
/// pesos de rareza, luego la especie dentro del tier, luego el shiny. La vida
/// no se sortea: es la de la zona.
public struct SpawnService {
    private let pokedex: Pokedex
    private let zones: ZoneCatalog

    public init(pokedex: Pokedex = .shared, zones: ZoneCatalog = .shared) {
        self.pokedex = pokedex
        self.zones = zones
    }

    /// Tiers que puede sortear una zona con este rango: los que tienen especies
    /// suyas y ya están abiertos por medallas.
    public func availableTiers(rank: TrainerRank, in zone: Zone) -> [Rarity] {
        let present = Set(pool(zone).map(\.rarity))
        return Rarity.allCases.filter { $0.spawnsInTheWild && rank >= $0.requiredRank && present.contains($0) }
    }

    /// Elige tier entre los que la zona puede dar, con los pesos
    /// renormalizados: si una zona no tiene raros, su peso se reparte entre
    /// los demás en vez de sortear en vacío.
    public func rollTier<R: RandomProvider>(rank: TrainerRank, in zone: Zone, using rng: inout R) -> Rarity? {
        let tiers = availableTiers(rank: rank, in: zone)
        guard !tiers.isEmpty else { return nil }
        let total = tiers.reduce(0.0) { $0 + $1.spawnWeight }
        var roll = rng.nextUnit() * total
        for tier in tiers {
            roll -= tier.spawnWeight
            if roll <= 0 { return tier }
        }
        return tiers[tiers.count - 1]
    }

    /// Lo que vive en una zona y puede salir: formas base y nada legendario.
    /// Un salvaje arranca su línea, y los legendarios son hitos con sitio y
    /// requisito.
    public func pool(_ zone: Zone) -> [Pokemon] {
        zone.species
            .compactMap { pokedex[$0] }
            .filter { $0.isBaseForm && $0.rarity.spawnsInTheWild }
            .sorted { $0.id < $1.id }
    }

    /// Un rival de la zona en la que estás. La zona decide **quién** sale
    /// (con la rareza como peso) y **cuánto aguanta**: dentro de una zona
    /// todos los salvajes tienen la misma vida, como las rutas de PokéClicker.
    public func spawn<R: RandomProvider>(
        zone: Zone,
        rank: TrainerRank,
        using rng: inout R,
        now: Date = Date()
    ) -> WildEncounter {
        var candidates = pool(zone)
        if let tier = rollTier(rank: rank, in: zone, using: &rng) {
            candidates = candidates.filter { $0.rarity == tier }
        }
        // Sin candidatas no hay combate, así que una zona vacía cae a la
        // primera. No debería pasar nunca —hay un test que lo fija— pero un
        // hueco de datos no puede dejar al jugador sin rival.
        if candidates.isEmpty { candidates = pool(zones.inUnlockOrder[0]) }
        let species = candidates[rng.nextInt(in: 0...(candidates.count - 1))]
        let shiny = rng.nextUnit() < GameRules.shinyProbability
        return WildEncounter(
            speciesID: species.id,
            isShiny: shiny,
            rarity: species.rarity,
            maxHP: zones.hp(of: zone),
            spawnedAt: now
        )
    }
}
