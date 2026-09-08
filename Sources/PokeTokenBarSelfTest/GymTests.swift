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
    ]

    private static let catalog = GymCatalog.shared
    private static let dex = Pokedex.shared
    private static let chart = TypeChart.shared
    private static let combat = GymCombat()

    static func testCatalogIntegrity() {
        expectEqual(catalog.count, 16, "8 de Johto + 8 de Kanto")
        expectEqual(Set(catalog.all.map(\.id)).count, 16, "ids únicos")
        expectEqual(Set(catalog.all.map(\.medal)).count, 16, "medallas únicas")
        expectEqual(catalog.all.map(\.order), Array(1...16), "orden consecutivo y ordenado")
        expectEqual(catalog.all.filter { $0.region == "johto" }.count, 8)
        expectEqual(catalog.all.filter { $0.region == "kanto" }.count, 8)
        expectTrue(
            catalog.all.prefix(8).allSatisfy { $0.region == "johto" },
            "Johto va primero, como en Gen 2"
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
        expectEqual(catalog.next(defeated: [])?.id, "johto-violet")
        expectEqual(catalog.next(defeated: ["johto-violet"])?.id, "johto-azalea")
        // Derrotar uno de más adelante no salta los de antes.
        expectEqual(catalog.next(defeated: ["kanto-pewter"])?.id, "johto-violet")
        expectNil(catalog.next(defeated: Set(catalog.all.map(\.id))), "con todos, no hay siguiente")
        expectEqual(catalog.medals(defeated: ["johto-violet", "johto-azalea"]).count, 2)
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

    static func testSpawnGateByRank() {
        let spawner = SpawnService()
        expectEqual(spawner.availableTiers(rank: .novato), [.common, .uncommon])
        expectEqual(spawner.availableTiers(rank: .entrenador), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(rank: .veterano), [.common, .uncommon, .rare])
        expectEqual(spawner.availableTiers(rank: .ace), Rarity.allCases)

        // Lo que cambia respecto a hoy: los tokens ya no abren nada por su cuenta.
        expectEqual(
            spawner.availableTiers(rank: TrainerRank.rank(forMedals: 0)),
            [.common, .uncommon],
            "sin medallas no hay raros ni legendarios, por muchos tokens que lleves"
        )
    }

    static func testAbsorptionBlocksWeakMatchups() {
        // Brock: absorción 0,75 en el orden 9.
        let brock = catalog["kanto-pewter"]!
        expectEqual(brock.absorption, 0.75, accuracy: 0.001)
        expectTrue(combat.isBlocked(matchup: 0.25, absorption: brock.absorption))
        expectTrue(combat.isBlocked(matchup: 0.5, absorption: brock.absorption))
        expectFalse(combat.isBlocked(matchup: 1, absorption: brock.absorption))
        expectEqual(combat.damagePerToken(matchup: 1, absorption: brock.absorption), 0.25, accuracy: 0.001)
        expectEqual(combat.damagePerToken(matchup: 2, absorption: brock.absorption), 1.25, accuracy: 0.001)
        expectEqual(combat.damagePerToken(matchup: 4, absorption: brock.absorption), 3.25, accuracy: 0.001)
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
        let giovanni = try unwrap(catalog["kanto-viridian"])
        expectEqual(giovanni.order, 16)
        expectTrue(combat.isBlocked(matchup: 1, absorption: giovanni.absorption, stage: .two),
                   "ni evolucionado al máximo basta un cruce neutro contra el último")
        expectFalse(combat.isBlocked(matchup: 2, absorption: giovanni.absorption, stage: .two))
        expectFalse(combat.isBlocked(matchup: 4, absorption: giovanni.absorption))
    }
}
