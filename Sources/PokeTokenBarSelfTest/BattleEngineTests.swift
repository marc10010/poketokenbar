import Foundation
import PokeTokenBarCore

@MainActor
enum BattleEngineTests: TestSuite {
    static let suiteName = "BattleEngine"

    static let tests: [(String, () throws -> Void)] = [
        ("one token is one point of damage", testOneTokenIsOnePointOfDamage),
        ("al caer, el motor lo reporta y saca otro", testExactKillCapturesAndRespawns),
        ("overkill carries over into the next rival", testOverkillCarriesOverIntoTheNextRival),
        ("a single huge event can capture several rivals", testASingleHugeEventCanCaptureSeveralRivals),
        ("shiny is preserved on capture", testShinyIsPreservedOnCapture),
        ("nil encounter spawns before taking damage", testNilEncounterSpawnsBeforeTakingDamage),
        ("zero and negative damage are no ops", testZeroAndNegativeDamageAreNoOps),
    ]

    private static let engine = BattleEngine()
    /// La primera zona: el motor necesita una para saber de dónde saca el
    /// rival siguiente cuando cae el de ahora.
    private static let zone = ZoneCatalog.shared.inUnlockOrder[0]

    private static func encounter(hp: Int, speciesID: Int = 19) -> WildEncounter {
        WildEncounter(speciesID: speciesID, isShiny: false, rarity: .common, maxHP: hp)
    }

    static func testOneTokenIsOnePointOfDamage() {
        var rng = SeededRandomProvider(seed: 1)
        let result = engine.apply(damage: 1_500, to: encounter(hp: 10_000), zone: zone, rank: .campeon, using: &rng)
        expectEqual(result.damageApplied, 1_500)
        expectEqual(result.encounter?.currentHP, 8_500)
        expectTrue(result.defeated.isEmpty)
    }

    static func testExactKillCapturesAndRespawns() {
        var rng = SeededRandomProvider(seed: 2)
        let result = engine.apply(damage: 10_000, to: encounter(hp: 10_000), zone: zone, rank: .campeon, using: &rng)
        expectEqual(result.defeated.count, 1)
        expectEqual(result.defeated.first?.speciesID, 19, "quedárselo o no lo decide la caja, no el motor")
        expectEqual(result.encounter?.currentHP, result.encounter?.maxHP, "el rival nuevo aparece intacto")
        expectFalse(result.encounter?.isFainted ?? true)
    }

    static func testOverkillCarriesOverIntoTheNextRival() {
        var rng = SeededRandomProvider(seed: 3)
        let result = engine.apply(damage: 10_500, to: encounter(hp: 10_000), zone: zone, rank: .campeon, using: &rng)
        expectEqual(result.damageApplied, 10_500, "ningún token se pierde")
        expectEqual(result.defeated.count, 1)
        let next = try? unwrap(result.encounter)
        expectEqual((next?.maxHP ?? 0) - (next?.currentHP ?? 0), 500)
    }

    static func testASingleHugeEventCanCaptureSeveralRivals() {
        var rng = SeededRandomProvider(seed: 4)
        let result = engine.apply(damage: 400_000, to: encounter(hp: 10_000), zone: zone, rank: .campeon, using: &rng)
        expectGreaterThan(result.defeated.count, 1)
        expectEqual(result.damageApplied, 400_000)
    }

    static func testShinyIsPreservedOnCapture() {
        var rng = SeededRandomProvider(seed: 5)
        let shiny = WildEncounter(speciesID: 25, isShiny: true, rarity: .uncommon, maxHP: 100)
        let result = engine.apply(damage: 100, to: shiny, zone: zone, rank: .campeon, using: &rng)
        expectEqual(result.defeated.first?.isShiny, true)
    }

    static func testNilEncounterSpawnsBeforeTakingDamage() {
        var rng = SeededRandomProvider(seed: 6)
        let result = engine.apply(damage: 10, to: nil, zone: zone, rank: .campeon, using: &rng)
        expectNotNil(result.encounter)
        expectEqual(result.damageApplied, 10)
    }

    static func testZeroAndNegativeDamageAreNoOps() {
        var rng = SeededRandomProvider(seed: 7)
        let start = encounter(hp: 10_000)
        for damage in [0, -50] {
            let result = engine.apply(damage: damage, to: start, zone: zone, rank: .campeon, using: &rng)
            expectEqual(result.damageApplied, 0)
            expectEqual(result.encounter?.currentHP, 10_000)
            expectTrue(result.defeated.isEmpty)
        }
    }
}
