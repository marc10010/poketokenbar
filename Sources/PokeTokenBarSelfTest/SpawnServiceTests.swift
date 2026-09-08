import Foundation
import PokeTokenBarCore

@MainActor
enum SpawnServiceTests: TestSuite {
    static let suiteName = "SpawnService"

    static let tests: [(String, () throws -> Void)] = [
        ("el gate es el rango, no los tokens", testTierGatesByRank),
        ("los tiers bloqueados no salen", testGatedTiersNeverSpawn),
        ("el 2 % legendario se reparte entre los demás", testSpawnRatiosRedistributeTheLegendaryShare),
        ("hp stays inside the tier range", testHPStaysInsideTheTierRange),
        ("shiny rate is about one percent", testShinyRateIsAboutOnePercent),
    ]

    private static let spawner = SpawnService()

    static func testTierGatesByRank() {
        expectEqual(spawner.availableTiers(rank: .novato), [.common, .uncommon])
        expectEqual(spawner.availableTiers(rank: .entrenador), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(rank: .veterano), [.common, .uncommon, .rare])
        // Ni con el rango máximo aparece el tier legendario: son hitos.
        expectEqual(spawner.availableTiers(rank: .ace), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(rank: .campeon), [.common, .uncommon, .rare])
    }

    static func testGatedTiersNeverSpawn() {
        var rng = SeededRandomProvider(seed: 99)
        for _ in 0..<3_000 {
            let encounter = spawner.spawn(rank: .novato, using: &rng)
            expectTrue([.common, .uncommon].contains(encounter.rarity))
        }
    }

    /// Los legendarios ya no salen en libertad: son hitos con sitio y
    /// requisito. Su 2 % se reparte entre los tiers que sí aparecen, en
    /// proporción a su peso, así que las cifras del spec se normalizan sobre
    /// 0,98 en vez de sobre 1.
    static func testSpawnRatiosRedistributeTheLegendaryShare() {
        var rng = SeededRandomProvider(seed: 4242)
        var counts: [Rarity: Int] = [:]
        let samples = 200_000
        for _ in 0..<samples {
            counts[spawner.rollTier(rank: .campeon, using: &rng), default: 0] += 1
        }

        expectEqual(counts[.legendary] ?? 0, 0, "un legendario no puede aparecer de rival salvaje")

        let spawnable = Rarity.allCases.filter(\.spawnsInTheWild)
        let total = spawnable.reduce(0.0) { $0 + $1.spawnWeight }
        expectEqual(total, 0.98, accuracy: 0.0001)
        for rarity in spawnable {
            let observed = Double(counts[rarity] ?? 0) / Double(samples)
            expectEqual(observed, rarity.spawnWeight / total, accuracy: 0.01, "\(rarity)")
        }
    }

    static func testHPStaysInsideTheTierRange() {
        var rng = SeededRandomProvider(seed: 7)
        for _ in 0..<5_000 {
            let encounter = spawner.spawn(rank: .campeon, using: &rng)
            expectTrue(
                encounter.rarity.hpRange.contains(encounter.maxHP),
                "\(encounter.rarity) fuera de rango: \(encounter.maxHP)"
            )
            expectEqual(encounter.currentHP, encounter.maxHP)
        }
    }

    static func testShinyRateIsAboutOnePercent() {
        var rng = SeededRandomProvider(seed: 1234)
        var shinies = 0
        let samples = 100_000
        for _ in 0..<samples where spawner.spawn(rank: .campeon, using: &rng).isShiny {
            shinies += 1
        }
        expectEqual(Double(shinies) / Double(samples), 0.01, accuracy: 0.002)
    }
}
