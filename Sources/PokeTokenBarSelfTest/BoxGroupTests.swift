import Foundation
import PokeTokenBarCore

@MainActor
enum BoxGroupTests: TestSuite {
    static let suiteName = "BoxGroup"

    static let tests: [(String, () throws -> Void)] = [
        ("las capturas repetidas se apilan", testDuplicatesStack),
        ("el variocolor va aparte", testShinyIsItsOwnGroup),
        ("orden pokédex", testDexOrder),
        ("agrupa por especie capturada", testGroupsByCapturedSpecies),
        ("la caja no cambia con el histórico global", testBoxIgnoresGlobalHistory),
        ("la etapa ganada separa y se queda pegada", testEarnedStageSplitsAndSticks),
        ("el representante es el más reciente", testRepresentativeIsNewest),
        ("mil capturas de lo mismo siguen siendo un hueco", testGrowthIsBoundedByForms),
    ]

    private static func captured(
        _ speciesID: Int,
        shiny: Bool = false,
        seed: UInt64 = 1,
        secondsAgo: TimeInterval = 0,
        earned: Int = 0
    ) -> CapturedPokemon {
        CapturedPokemon(
            speciesID: speciesID,
            isShiny: shiny,
            capturedAt: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            capturedAtTotalTokens: 0,
            evolutionSeed: seed,
            tokensEarned: earned
        )
    }

    private static let dex = Pokedex.shared

    private static let evolution = EvolutionService()

    private static func group(_ box: [CapturedPokemon]) -> [BoxGroup] {
        BoxGroup.group(box, pokedex: dex, evolution: evolution)
    }

    static func testDuplicatesStack() {
        let groups = group([captured(19), captured(19), captured(19)])
        expectEqual(groups.count, 1)
        expectEqual(groups.first?.count, 3)
        expectEqual(groups.first?.species.id, 19)
    }

    static func testShinyIsItsOwnGroup() {
        let groups = group([captured(19), captured(19), captured(19, shiny: true)])
        expectEqual(groups.count, 2)
        expectEqual(groups.first(where: { $0.isShiny })?.count, 1)
        expectEqual(groups.first(where: { !$0.isShiny })?.count, 2)
    }

    static func testDexOrder() {
        let groups = group([captured(151), captured(19), captured(92), captured(1)])
        expectEqual(groups.map(\.species.id), [1, 19, 92, 151])
    }

    static func testGroupsByCapturedSpecies() {
        // Un Bulbasaur y un Venusaur capturados son especies distintas y ocupan
        // huecos distintos: la caja muestra lo que cazaste, no una forma derivada.
        let groups = group([captured(1), captured(3)])
        expectEqual(groups.count, 2)
        expectEqual(groups.map(\.species.id), [1, 3])
    }

    /// El bug que esto evita: un Pineco recién capturado aparecía como
    /// Forretress y un Cubone como Marowak solo porque el jugador llevaba
    /// 300k tokens con OTRO compañero.
    static func testBoxIgnoresGlobalHistory() {
        let box = [captured(204), captured(104), captured(133), captured(133, seed: 999)]
        let groups = group(box)
        expectEqual(groups.map(\.species.id), [104, 133, 204], "Cubone, Eevee y Pineco tal cual")
        expectEqual(groups.first(where: { $0.species.id == 133 })?.count, 2, "sin tokens ganados, los Eevee no se separan")
        expectTrue(groups.allSatisfy { !$0.hasEvolved }, "nada capturado sale evolucionado")
        expectEqual(groups.reduce(0) { $0 + $1.count }, box.count)
    }

    static func testRepresentativeIsNewest() throws {
        let old = captured(19, secondsAgo: 900)
        let newest = captured(19, secondsAgo: 0)
        let groups = group([old, newest])
        expectEqual(try unwrap(groups.first).representative.id, newest.id)
        expectEqual(try unwrap(groups.first).latestCapturedAt, newest.capturedAt)
    }

    static func testGrowthIsBoundedByForms() {
        let box = (0..<1_000).map { captured(19, seed: UInt64($0)) }
        let groups = group(box)
        expectEqual(groups.count, 1, "la rejilla tiene techo en formas, no en capturas")
        expectEqual(groups.first?.count, 1_000)
    }

    /// Dos Cubone, uno que ha ganado tokens y otro no: se ven distinto, así que
    /// van a huecos distintos, y el evolucionado lo sigue estando aunque el
    /// jugador cambie de compañero (su `tokensEarned` no baja).
    static func testEarnedStageSplitsAndSticks() throws {
        let groups = group([
            captured(104, earned: 0),
            captured(104, seed: 2, earned: 250_000),
            captured(104, seed: 3, earned: 250_000),
        ])
        expectEqual(groups.count, 2)

        let base = try unwrap(groups.first { $0.stage == .base })
        expectEqual(base.count, 1)
        expectEqual(base.displayForm.id, 104, "Cubone")
        expectFalse(base.hasEvolved)

        let evolved = try unwrap(groups.first { $0.stage == .one })
        expectEqual(evolved.count, 2)
        expectEqual(evolved.displayForm.id, 105, "Marowak")
        expectEqual(evolved.species.id, 104, "la especie capturada sigue siendo Cubone")
        expectTrue(evolved.hasEvolved)
        expectEqual(evolved.representative.tokensEarned, 250_000, "representa al más adelantado")
    }
}
