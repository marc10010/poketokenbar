import Foundation
import PokeTokenBarCore

@MainActor
enum BattleEngineTests: TestSuite {
    static let suiteName = "BattleEngine"

    static let tests: [(String, () throws -> Void)] = [
        ("one token is one point of damage", testOneTokenIsOnePointOfDamage),
        ("exact kill captures and respawns", testExactKillCapturesAndRespawns),
        ("overkill carries over into the next rival", testOverkillCarriesOverIntoTheNextRival),
        ("a single huge event can capture several rivals", testASingleHugeEventCanCaptureSeveralRivals),
        ("shiny is preserved on capture", testShinyIsPreservedOnCapture),
        ("nil encounter spawns before taking damage", testNilEncounterSpawnsBeforeTakingDamage),
        ("zero and negative damage are no ops", testZeroAndNegativeDamageAreNoOps),
    ]

    private static let engine = BattleEngine()

    private static func encounter(hp: Int, speciesID: Int = 19) -> WildEncounter {
        WildEncounter(speciesID: speciesID, isShiny: false, rarity: .common, maxHP: hp)
    }

    static func testOneTokenIsOnePointOfDamage() {
        var rng = SeededRandomProvider(seed: 1)
        let result = engine.apply(damage: 1_500, to: encounter(hp: 10_000), totalTokensAfter: 1_500, using: &rng)
        expectEqual(result.damageApplied, 1_500)
        expectEqual(result.encounter?.currentHP, 8_500)
        expectTrue(result.captures.isEmpty)
    }

    static func testExactKillCapturesAndRespawns() {
        var rng = SeededRandomProvider(seed: 2)
        let result = engine.apply(damage: 10_000, to: encounter(hp: 10_000), totalTokensAfter: 10_000, using: &rng)
        expectEqual(result.captures.count, 1)
        expectEqual(result.captures.first?.speciesID, 19)
        expectEqual(result.encounter?.currentHP, result.encounter?.maxHP, "el rival nuevo aparece intacto")
        expectFalse(result.encounter?.isFainted ?? true)
    }

    static func testOverkillCarriesOverIntoTheNextRival() {
        var rng = SeededRandomProvider(seed: 3)
        let result = engine.apply(damage: 10_500, to: encounter(hp: 10_000), totalTokensAfter: 10_500, using: &rng)
        expectEqual(result.damageApplied, 10_500, "ningún token se pierde")
        expectEqual(result.captures.count, 1)
        let next = try? unwrap(result.encounter)
        expectEqual((next?.maxHP ?? 0) - (next?.currentHP ?? 0), 500)
    }

    static func testASingleHugeEventCanCaptureSeveralRivals() {
        var rng = SeededRandomProvider(seed: 4)
        let result = engine.apply(damage: 400_000, to: encounter(hp: 10_000), totalTokensAfter: 400_000, using: &rng)
        expectGreaterThan(result.captures.count, 1)
        expectEqual(result.damageApplied, 400_000)
    }

    static func testShinyIsPreservedOnCapture() {
        var rng = SeededRandomProvider(seed: 5)
        let shiny = WildEncounter(speciesID: 25, isShiny: true, rarity: .uncommon, maxHP: 100)
        let result = engine.apply(damage: 100, to: shiny, totalTokensAfter: 100, using: &rng)
        expectEqual(result.captures.first?.isShiny, true)
    }

    static func testNilEncounterSpawnsBeforeTakingDamage() {
        var rng = SeededRandomProvider(seed: 6)
        let result = engine.apply(damage: 10, to: nil, totalTokensAfter: 10, using: &rng)
        expectNotNil(result.encounter)
        expectEqual(result.damageApplied, 10)
    }

    static func testZeroAndNegativeDamageAreNoOps() {
        var rng = SeededRandomProvider(seed: 7)
        let start = encounter(hp: 10_000)
        for damage in [0, -50] {
            let result = engine.apply(damage: damage, to: start, totalTokensAfter: 0, using: &rng)
            expectEqual(result.damageApplied, 0)
            expectEqual(result.encounter?.currentHP, 10_000)
            expectTrue(result.captures.isEmpty)
        }
    }
}
