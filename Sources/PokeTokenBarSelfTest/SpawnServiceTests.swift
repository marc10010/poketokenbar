import Foundation
import PokeTokenBarCore

@MainActor
enum SpawnServiceTests: TestSuite {
    static let suiteName = "SpawnService"

    static let tests: [(String, () throws -> Void)] = [
        ("tier gates by global tokens", testTierGatesByGlobalTokens),
        ("gated tiers never spawn", testGatedTiersNeverSpawn),
        ("spawn ratios follow the spec once everything is unlocked", testSpawnRatiosFollowTheSpecOnceEverythingIsUnlocked),
        ("hp stays inside the tier range", testHPStaysInsideTheTierRange),
        ("shiny rate is about one percent", testShinyRateIsAboutOnePercent),
    ]

    private static let spawner = SpawnService()

    static func testTierGatesByGlobalTokens() {
        expectEqual(spawner.availableTiers(totalTokens: 0), [.common, .uncommon])
        expectEqual(spawner.availableTiers(totalTokens: 200_000), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(totalTokens: 1_999_999), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(totalTokens: 2_000_000), Rarity.allCases)
    }

    static func testGatedTiersNeverSpawn() {
        var rng = SeededRandomProvider(seed: 99)
        for _ in 0..<3_000 {
            let encounter = spawner.spawn(totalTokens: 150_000, using: &rng)
            expectTrue([.common, .uncommon].contains(encounter.rarity))
        }
    }

    static func testSpawnRatiosFollowTheSpecOnceEverythingIsUnlocked() {
        var rng = SeededRandomProvider(seed: 4242)
        var counts: [Rarity: Int] = [:]
        let samples = 200_000
        for _ in 0..<samples {
            counts[spawner.rollTier(totalTokens: 5_000_000, using: &rng), default: 0] += 1
        }
        for rarity in Rarity.allCases {
            let observed = Double(counts[rarity] ?? 0) / Double(samples)
            expectEqual(observed, rarity.spawnWeight, accuracy: 0.01, "\(rarity)")
        }
    }

    static func testHPStaysInsideTheTierRange() {
        var rng = SeededRandomProvider(seed: 7)
        for _ in 0..<5_000 {
            let encounter = spawner.spawn(totalTokens: 10_000_000, using: &rng)
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
        for _ in 0..<samples where spawner.spawn(totalTokens: 3_000_000, using: &rng).isShiny {
            shinies += 1
        }
        expectEqual(Double(shinies) / Double(samples), 0.01, accuracy: 0.002)
    }
}
