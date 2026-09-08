import Foundation
import PokeTokenBarCore

@MainActor
enum PokedexEntryTests: TestSuite {
    static let suiteName = "Pokédex completa"

    static let tests: [(String, () throws -> Void)] = [
        ("tiene los 251 huecos en orden", testAllEntries),
        ("sin nada, todo está sin ver", testEmptyState),
        ("cuenta la especie capturada y la forma que se ve", testCapturedAndDisplayedForm),
        ("lo vencido sin quedárselo queda como visto", testDefeatedButNotCaptured),
        ("el filtro recorta sin inventar huecos", testFilter),
    ]

    private static let dex = Pokedex.shared
    private static let evolution = EvolutionService()

    private static func captured(_ speciesID: Int, earned: Int = 0) -> CapturedPokemon {
        CapturedPokemon(speciesID: speciesID, isShiny: false, capturedAtTotalTokens: 0, evolutionSeed: 3, tokensEarned: earned)
    }

    private static func build(box: [CapturedPokemon] = [], defeats: [Int: Int] = [:]) -> [PokedexEntry] {
        PokedexEntry.build(
            pokedex: dex,
            boxGroups: BoxGroup.group(box, pokedex: dex, evolution: evolution),
            familyDefeats: defeats
        )
    }

    static func testAllEntries() {
        let entries = build()
        expectEqual(entries.count, 251)
        expectEqual(entries.map(\.species.id), Array(1...251))
    }

    static func testEmptyState() {
        let entries = build()
        expectTrue(entries.allSatisfy { $0.state == .unknown })
        expectEqual(entries.filter(\.isCaptured).count, 0)
    }

    static func testCapturedAndDisplayedForm() throws {
        // Un Squirtle capturado que ya es Wartortle llena los dos huecos, pero
        // Blastoise sigue vacío: marcar la línea entera contaría formas que no
        // has visto nunca.
        let entries = build(box: [captured(7, earned: 250_000)])
        expectEqual(try unwrap(entries.first { $0.species.id == 7 }).state, PokedexEntry.State.captured)
        expectEqual(try unwrap(entries.first { $0.species.id == 8 }).state, PokedexEntry.State.captured)
        expectEqual(try unwrap(entries.first { $0.species.id == 9 }).state, PokedexEntry.State.unknown, "Blastoise no")
        expectEqual(entries.filter(\.isCaptured).count, 2)
    }

    static func testDefeatedButNotCaptured() throws {
        // Le has ganado a la línea de Pidgey pero no se quedó: los tres huecos
        // de la línea salen como vistos, no como capturados.
        let entries = build(defeats: [16: 3])
        for id in [16, 17, 18] {
            let entry = try unwrap(entries.first { $0.species.id == id })
            expectEqual(entry.state, PokedexEntry.State.defeated, "#\(id)")
            expectEqual(entry.defeats, 3)
        }
        expectEqual(entries.filter(\.isCaptured).count, 0)
        expectEqual(entries.filter { $0.state != .unknown }.count, 3)
    }

    static func testFilter() throws {
        let entries = build(box: [captured(7)], defeats: [16: 1])
        var filter = PokedexFilter()

        filter.query = "squirtle"
        expectEqual(filter.apply(to: entries).map(\.species.id), [7])
        filter.query = "#150"
        expectEqual(filter.apply(to: entries).map(\.species.id), [150])

        filter = PokedexFilter()
        filter.onlyMissing = true
        let missing = filter.apply(to: entries)
        expectEqual(missing.count, 250, "solo el Squirtle está en la caja")
        expectFalse(missing.contains { $0.species.id == 7 })

        filter = PokedexFilter()
        filter.onlyCaptured = true
        expectEqual(filter.apply(to: entries).map(\.species.id), [7])

        filter = PokedexFilter()
        filter.generation = 2
        let gen2 = filter.apply(to: entries)
        expectEqual(gen2.count, 100)
        expectTrue(gen2.allSatisfy { $0.species.id >= 152 })

        filter = PokedexFilter()
        filter.types = ["dragon"]
        let dragons = filter.apply(to: entries)
        expectTrue(dragons.allSatisfy { $0.species.types.contains("dragon") })
        expectGreaterThan(dragons.count, 0)

        // Invariante: filtrar nunca inventa ni duplica huecos.
        for query in ["", "a", "999", "#", "no-existe"] {
            filter = PokedexFilter()
            filter.query = query
            let result = filter.apply(to: entries)
            expectTrue(result.count <= entries.count)
            expectEqual(Set(result.map(\.id)).count, result.count)
        }
    }
}
