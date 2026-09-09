import Foundation

/// Sortea rivales: primero el tier (con gates por tokens globales), luego la
/// especie dentro del tier, luego HP y shiny.
public struct SpawnService {
    private let pokedex: Pokedex
    private let zones: ZoneCatalog

    public init(pokedex: Pokedex = .shared, zones: ZoneCatalog = .shared) {
        self.pokedex = pokedex
        self.zones = zones
    }

    /// Tiers disponibles según el rango. Acumular tokens no desbloquea nada:
    /// hacen falta medallas.
    public func availableTiers(rank: TrainerRank) -> [Rarity] {
        Rarity.allCases.filter { $0.spawnsInTheWild && rank >= $0.requiredRank }
    }

    /// Elige tier respetando los ratios del spec. Si un tier está bloqueado,
    /// su peso se redistribuye entre los disponibles en vez de reintentar.
    public func rollTier<R: RandomProvider>(rank: TrainerRank, using rng: inout R) -> Rarity {
        let tiers = availableTiers(rank: rank)
        guard !tiers.isEmpty else { return .common }
        let weightTotal = tiers.reduce(0.0) { $0 + $1.spawnWeight }
        var roll = rng.nextUnit() * weightTotal
        for tier in tiers {
            roll -= tier.spawnWeight
            if roll <= 0 { return tier }
        }
        return tiers[tiers.count - 1]
    }

    /// Tier en el que se ofrece una especie sin zona: el más difícil entre
    /// "raro" y el suyo. `sortIndex` es menor cuanto más raro, así que el más
    /// difícil es el de índice más bajo.
    public func fallbackTier(for species: Pokemon) -> Rarity {
        species.rarity.sortIndex <= Rarity.rare.sortIndex ? species.rarity : .rare
    }

    /// Candidatas de un tier con las zonas abiertas de por medio.
    ///
    /// Una especie sin zona (sin encuentro salvaje en Gen 1/2) entra en el tier
    /// más difícil entre "raro" y el suyo: así ninguna se vuelve incompletable
    /// por un hueco del reparto, pero un legendario no se abarata a raro.
    public func candidates(rarity: Rarity, access: ZoneAccess) -> [Pokemon] {
        let tierPool = pokedex.spawnCandidates(rarity: rarity)
        var available = tierPool.filter { zones.isAvailable($0.id, access) }

        for id in zones.unassigned {
            guard let species = pokedex[id], species.isBaseForm, !species.isLegendary else { continue }
            guard fallbackTier(for: species) == rarity else { continue }
            if !available.contains(where: { $0.id == id }) { available.append(species) }
        }

        // Nunca dejar un tier sin candidatas: el combate no puede quedarse sin
        // rival por un hueco de datos.
        return available.isEmpty ? tierPool : available.sorted { $0.id < $1.id }
    }

    /// Lo que puede aparecer en una zona enfocada: **todas** sus especies a
    /// partes iguales, sin sortear tier ni filtrar por rango.
    ///
    /// Fuera quedan las formas evolucionadas (un salvaje arranca su línea) y
    /// los legendarios, que no es un filtro de esta mecánica: no aparecen en
    /// libertad en ningún caso, son hitos con sitio y requisito.
    public func focusPool(_ zone: Zone) -> [Pokemon] {
        zone.species
            .compactMap { pokedex[$0] }
            .filter { $0.isBaseForm && $0.rarity.spawnsInTheWild }
            .sorted { $0.id < $1.id }
    }

    public func spawn<R: RandomProvider>(
        rank: TrainerRank,
        access: ZoneAccess = ZoneAccess(medals: 0, kantoOpen: false, isChampion: false),
        focus: Zone? = nil,
        using rng: inout R,
        now: Date = Date()
    ) -> WildEncounter {
        // Zona enfocada: sale cualquiera de las suyas, a partes iguales. La
        // probabilidad de una concreta es su tamaño y nada más, así que no hay
        // constante que ajustar ni que explicar.
        if let focus, access.opens(focus) {
            let pool = focusPool(focus)
            if !pool.isEmpty {
                let species = pool[rng.nextInt(in: 0...(pool.count - 1))]
                let hp = rng.nextInt(in: species.rarity.hpRange)
                let shiny = rng.nextUnit() < GameRules.shinyProbability
                return WildEncounter(
                    speciesID: species.id,
                    isShiny: shiny,
                    rarity: species.rarity,
                    maxHP: hp,
                    spawnedAt: now
                )
            }
        }

        let tier = rollTier(rank: rank, using: &rng)
        let pool = candidates(rarity: tier, access: access)
        let species = pool[rng.nextInt(in: 0...(pool.count - 1))]
        let hp = rng.nextInt(in: tier.hpRange)
        let shiny = rng.nextUnit() < GameRules.shinyProbability
        return WildEncounter(speciesID: species.id, isShiny: shiny, rarity: tier, maxHP: hp, spawnedAt: now)
    }
}
