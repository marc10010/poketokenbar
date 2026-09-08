import Foundation

/// Sortea rivales: primero el tier (con gates por tokens globales), luego la
/// especie dentro del tier, luego HP y shiny.
public struct SpawnService {
    private let pokedex: Pokedex

    public init(pokedex: Pokedex = .shared) {
        self.pokedex = pokedex
    }

    /// Tiers disponibles según el rango. Acumular tokens no desbloquea nada:
    /// hacen falta medallas.
    public func availableTiers(rank: TrainerRank) -> [Rarity] {
        Rarity.allCases.filter { rank >= $0.requiredRank }
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

    public func spawn<R: RandomProvider>(rank: TrainerRank, using rng: inout R, now: Date = Date()) -> WildEncounter {
        let tier = rollTier(rank: rank, using: &rng)
        let pool = pokedex.spawnCandidates(rarity: tier)
        let species = pool[rng.nextInt(in: 0...(pool.count - 1))]
        let hp = rng.nextInt(in: tier.hpRange)
        let shiny = rng.nextUnit() < GameRules.shinyProbability
        return WildEncounter(speciesID: species.id, isShiny: shiny, rarity: tier, maxHP: hp, spawnedAt: now)
    }
}
