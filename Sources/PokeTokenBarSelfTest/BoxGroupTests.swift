import Foundation
import PokeTokenBarCore

@MainActor
enum BoxGroupTests: TestSuite {
    static let suiteName = "BoxGroup"

    static let tests: [(String, () throws -> Void)] = [
        ("las capturas repetidas se apilan", testDuplicatesStack),
        ("el variocolor va aparte", testShinyIsItsOwnGroup),
        ("orden pokédex", testDexOrder),
        ("agrupa por forma visible, no por especie capturada", testGroupsByVisibleForm),
        ("las ramas evolutivas distintas se separan", testDivergentBranchesSplit),
        ("el representante es el más reciente", testRepresentativeIsNewest),
        ("mil capturas de lo mismo siguen siendo un hueco", testGrowthIsBoundedByForms),
    ]

    private static let evolution = EvolutionService()

    private static func captured(
        _ speciesID: Int,
        shiny: Bool = false,
        seed: UInt64 = 1,
        secondsAgo: TimeInterval = 0
    ) -> CapturedPokemon {
        CapturedPokemon(
            speciesID: speciesID,
            isShiny: shiny,
            capturedAt: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            capturedAtTotalTokens: 0,
            evolutionSeed: seed
        )
    }

    private static func group(_ box: [CapturedPokemon], totalTokens: Int = 0) -> [BoxGroup] {
        BoxGroup.group(box, totalTokens: totalTokens, evolution: evolution)
    }

    static func testDuplicatesStack() {
        let groups = group([captured(19), captured(19), captured(19)])
        expectEqual(groups.count, 1)
        expectEqual(groups.first?.count, 3)
        expectEqual(groups.first?.form.id, 19)
    }

    static func testShinyIsItsOwnGroup() {
        let groups = group([captured(19), captured(19), captured(19, shiny: true)])
        expectEqual(groups.count, 2)
        expectEqual(groups.first(where: { $0.isShiny })?.count, 1)
        expectEqual(groups.first(where: { !$0.isShiny })?.count, 2)
    }

    static func testDexOrder() {
        let groups = group([captured(151), captured(19), captured(92), captured(1)])
        expectEqual(groups.map(\.form.id), [1, 19, 92, 151])
    }

    static func testGroupsByVisibleForm() {
        // Un Bulbasaur y un Venusaur capturados son la misma línea: con poco
        // histórico los dos se dibujan como Bulbasaur y ocupan un solo hueco.
        let groups = group([captured(1), captured(3)])
        expectEqual(groups.count, 1)
        expectEqual(groups.first?.form.id, 1)
        expectEqual(groups.first?.count, 2)

        // Con histórico de etapa 2, ambos son Venusaur: sigue siendo un hueco.
        let evolved = group([captured(1), captured(3)], totalTokens: 5_000_000)
        expectEqual(evolved.count, 1)
        expectEqual(evolved.first?.form.id, 3)
    }

    static func testDivergentBranchesSplit() {
        // Eevee bifurca en cinco: dos ejemplares con semillas que dan ramas
        // distintas dejan de verse igual y por tanto se separan.
        let seeds = (0..<40).map { UInt64($0) * 7919 + 1 }
        let box = seeds.map { captured(133, seed: $0) }
        let base = group(box)
        expectEqual(base.count, 1, "sin evolucionar, todos son Eevee")

        let evolved = group(box, totalTokens: 500_000)
        expectGreaterThan(evolved.count, 1, "las ramas ya no se ven igual")
        expectEqual(evolved.reduce(0) { $0 + $1.count }, box.count, "no se pierde ninguna captura")
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
}
