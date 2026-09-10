import Foundation
import PokeTokenBarCore

@MainActor
enum GymTests: TestSuite {
    static let suiteName = "Gimnasios"

    static let tests: [(String, () throws -> Void)] = [
        ("el catálogo está completo y sin duplicados", testCatalogIntegrity),
        ("los pokémon estrella existen y sus tipos están en la tabla", testSignatureSpeciesAreReal),
        ("el HP cae en el rango pedido y la dificultad sube", testDifficultyRamp),
        ("el siguiente gimnasio es el primero sin derrotar", testNextGym),
        ("el rango sale de las medallas", testRankFromMedals),
        ("el gate de aparición sale del rango", testSpawnGateByRank),
        ("la absorción bloquea los cruces flojos", testAbsorptionBlocksWeakMatchups),
        ("un millón de tokens bloqueados no quitan ni un HP", testBlockedDealsNothing),
        ("la etapa evolutiva desbloquea cruces justos", testStageBonusUnblocks),
        ("los tokens necesarios cuadran con la tasa", testTokensNeeded),
        ("los gimnasios tardíos exigen ser eficaz", testLateGymsRequireEffectiveness),
        ("las medallas se cuentan por región sin reiniciar el total", testMedalsByRegion),
    ]

    private static let catalog = GymCatalog.shared
    private static let dex = Pokedex.shared
    private static let chart = TypeChart.shared
    private static let combat = GymCombat()

    /// Cada región tiene sus ocho, pero el total no se reinicia: el rango y
    /// los requisitos de las zonas cuentan las 16 seguidas. Es la duda que
    /// provocaba el "3/16" a secas.
    static func testMedalsByRegion() throws {
        expectEqual(catalog.regions, ["kanto", "johto"], "en orden de reto: Kanto primero")
        expectEqual(catalog.gyms(in: "kanto").count, 8)
        expectEqual(catalog.gyms(in: "johto").count, 8)

        let store = GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 6)
        )
        store.chooseStarter(speciesID: 7)

        var regions = store.medalsByRegion
        expectEqual(regions.map(\.region), ["kanto", "johto"])
        expectEqual(regions[0].earned, 0)
        expectTrue(regions[0].open, "Kanto está abierta desde el principio")
        expectTrue(!regions[1].open, "Johto no")
        expectEqual(regions[1].gate?.id, "kanto", "y dice qué la abre: el Alto Mando de Kanto")

        store.debugDefeatGyms(upTo: 8)
        regions = store.medalsByRegion
        expectEqual(regions[0].earned, 8, "las ocho de Kanto")
        expectEqual(regions[1].earned, 0)
        expectTrue(!regions[1].open, "con las 8 medallas Johto sigue cerrada: falta el barco")
        expectEqual(store.medals, 8, "y el total no se ha reiniciado")

        store.debugOpenRegion("johto")
        regions = store.medalsByRegion
        expectTrue(regions[1].open, "con el barco, Johto se abre")
        expectEqual(regions[1].gate, nil)

        store.debugDefeatGyms(upTo: 10)
        regions = store.medalsByRegion
        expectEqual(regions[0].earned, 8)
        expectEqual(regions[1].earned, 2, "dos de Johto")
        expectEqual(store.medals, 10, "que son 10 en total, no 2")
        expectEqual(store.rank, .campeon == store.rank ? store.rank : TrainerRank.rank(forMedals: 10))
    }

    static func testCatalogIntegrity() {
        expectEqual(catalog.count, 16, "8 de Kanto + 8 de Johto")
        expectEqual(Set(catalog.all.map(\.id)).count, 16, "ids únicos")
        expectEqual(Set(catalog.all.map(\.medal)).count, 16, "medallas únicas")
        expectEqual(catalog.all.map(\.order), Array(1...16), "orden consecutivo y ordenado")
        expectEqual(catalog.all.filter { $0.region == "johto" }.count, 8)
        expectEqual(catalog.all.filter { $0.region == "kanto" }.count, 8)
        expectTrue(
            catalog.all.prefix(8).allSatisfy { $0.region == "kanto" },
            "Kanto va primero: el orden de juego es Gen 1 y luego Gen 2"
        )
    }

    static func testSignatureSpeciesAreReal() {
        for gym in catalog.all {
            let species = dex[gym.signatureSpeciesID]
            expectNotNil(species, "\(gym.leader): #\(gym.signatureSpeciesID) no está en la Pokédex")
            guard let species else { continue }
            for type in species.types {
                expectTrue(chart.types.contains(type), "\(species.name): el tipo \(type) no está en la tabla")
            }
            expectTrue(chart.types.contains(gym.type), "\(gym.leader): tema \(gym.type) desconocido")
        }
    }

    static func testDifficultyRamp() {
        for gym in catalog.all {
            expectTrue(gym.hpRange.lowerBound >= 500_000, "\(gym.leader) baja de 500k")
            expectTrue(gym.hpRange.upperBound <= 1_000_000, "\(gym.leader) pasa de 1M")
            expectTrue(gym.hpRange.lowerBound < gym.hpRange.upperBound, "\(gym.leader) sin rango")
        }
        let hp = catalog.all.map(\.hpRange.lowerBound)
        expectEqual(hp, hp.sorted(), "el HP no decrece con el orden")
        let absorption = catalog.all.map(\.absorption)
        expectEqual(absorption, absorption.sorted(), "la absorción no decrece con el orden")
        expectTrue(
            catalog.all.prefix(9).allSatisfy { $0.absorption < 1 },
            "los nueve primeros deben poderse con cruce neutro"
        )
    }

    static func testNextGym() throws {
        expectEqual(catalog.next(defeated: [])?.id, "kanto-pewter")
        expectEqual(catalog.next(defeated: ["kanto-pewter"])?.id, "kanto-cerulean")
        // Derrotar uno de más adelante no salta los de antes.
        expectEqual(catalog.next(defeated: ["johto-violet"])?.id, "kanto-pewter")
        expectNil(catalog.next(defeated: Set(catalog.all.map(\.id))), "con todos, no hay siguiente")
        expectEqual(catalog.medals(defeated: ["kanto-pewter", "kanto-cerulean"]).count, 2)
    }

    static func testRankFromMedals() {
        expectEqual(TrainerRank.rank(forMedals: 0), .novato)
        expectEqual(TrainerRank.rank(forMedals: 1), .novato)
        expectEqual(TrainerRank.rank(forMedals: 2), .entrenador)
        expectEqual(TrainerRank.rank(forMedals: 4), .entrenador)
        expectEqual(TrainerRank.rank(forMedals: 5), .veterano)
        expectEqual(TrainerRank.rank(forMedals: 8), .ace)
        expectEqual(TrainerRank.rank(forMedals: 15), .ace)
        expectEqual(TrainerRank.rank(forMedals: 16), .campeon)
        expectEqual(TrainerRank.rank(forMedals: 99), .campeon, "no se sale del tope")

        expectEqual(TrainerRank.novato.next(medals: 0)?.missing, 2)
        expectEqual(TrainerRank.entrenador.next(medals: 3)?.missing, 2, "faltan 2 para veterano")
        expectNil(TrainerRank.campeon.next(medals: 16), "no hay rango por encima")
    }

    static func testSpawnGateByRank() throws {
        let spawner = SpawnService()
        // Una ruta con los tres tiers, para que el gate se lea.
        let zone = try unwrap(ZoneCatalog.shared["rutas-kanto-sur"])
        expectEqual(spawner.availableTiers(rank: .novato, in: zone), [.common, .uncommon])
        expectEqual(spawner.availableTiers(rank: .entrenador, in: zone), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(rank: .veterano, in: zone), [.common, .uncommon, .rare])
        // El tier legendario no está: los legendarios son hitos, no sorteo.
        expectEqual(spawner.availableTiers(rank: .ace, in: zone), [.common, .uncommon, .rare])
        expectFalse(Rarity.legendary.spawnsInTheWild)

        // Lo que cambia respecto a hoy: los tokens ya no abren nada por su cuenta.
        expectEqual(
            spawner.availableTiers(rank: TrainerRank.rank(forMedals: 0), in: zone),
            [.common, .uncommon],
            "sin medallas no hay raros ni legendarios, por muchos tokens que lleves"
        )
    }

    static func testAbsorptionBlocksWeakMatchups() {
        // Pryce: absorción 0,75, ya en la región 2 (orden 15).
        let pryce = catalog["johto-mahogany"]!
        expectEqual(pryce.absorption, 1.5, accuracy: 0.001)

        // Y el primero de todos, Brock, con la absorción más baja: un cruce
        // flojo no le hace nada, uno neutro sí.
        let brock = catalog["kanto-pewter"]!
        expectEqual(brock.absorption, 0.25, accuracy: 0.001)
        expectTrue(combat.isBlocked(matchup: 0.25, absorption: brock.absorption))
        expectFalse(combat.isBlocked(matchup: 0.5, absorption: brock.absorption))
        expectFalse(combat.isBlocked(matchup: 1, absorption: brock.absorption))
        expectEqual(combat.damagePerToken(matchup: 1, absorption: brock.absorption), 0.75, accuracy: 0.001)
        expectEqual(combat.damagePerToken(matchup: 2, absorption: brock.absorption), 1.75, accuracy: 0.001)
        expectEqual(combat.damagePerToken(matchup: 4, absorption: brock.absorption), 3.75, accuracy: 0.001)
    }

    static func testBlockedDealsNothing() {
        let damage = combat.damage(tokens: 1_000_000, matchup: 0.5, absorption: 0.75)
        expectEqual(damage, 0, "un millón de tokens con cruce flojo no mueven la barra")
        expectNil(combat.tokensNeeded(for: 500_000, matchup: 0.5, absorption: 0.75), "no hay cantidad que valga")
    }

    static func testStageBonusUnblocks() {
        // Cruce neutro contra absorción 1,0: bloqueado en etapa base, viable
        // en cuanto el compañero ha evolucionado.
        expectTrue(combat.isBlocked(matchup: 1, absorption: 1, stage: .base))
        expectFalse(combat.isBlocked(matchup: 1, absorption: 1, stage: .one))
        expectEqual(combat.damagePerToken(matchup: 1, absorption: 1, stage: .one), 0.25, accuracy: 0.001)
        expectEqual(combat.damagePerToken(matchup: 1, absorption: 1, stage: .two), 0.5, accuracy: 0.001)
    }

    static func testTokensNeeded() throws {
        let needed = try unwrap(combat.tokensNeeded(for: 600_000, matchup: 2, absorption: 0.5))
        expectEqual(needed, 400_000, "600k HP a 1,5 HP por token")
        expectEqual(combat.damage(tokens: needed, matchup: 2, absorption: 0.5), 600_000)
        expectEqual(combat.tokensNeeded(for: 0, matchup: 2, absorption: 0.5), 0)
    }

    static func testLateGymsRequireEffectiveness() throws {
        let clair = try unwrap(catalog["johto-blackthorn"])
        expectEqual(clair.order, 16, "la última es Clair, ya en la región 2")
        expectTrue(combat.isBlocked(matchup: 1, absorption: clair.absorption, stage: .two),
                   "ni evolucionado al máximo basta un cruce neutro contra el último")
        expectFalse(combat.isBlocked(matchup: 2, absorption: clair.absorption, stage: .two))
        expectFalse(combat.isBlocked(matchup: 4, absorption: clair.absorption))
    }
}
