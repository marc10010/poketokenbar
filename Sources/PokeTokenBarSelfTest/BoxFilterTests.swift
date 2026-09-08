import Foundation
import PokeTokenBarCore

@MainActor
enum BoxFilterTests: TestSuite {
    static let suiteName = "BoxFilter"

    static let tests: [(String, () throws -> Void)] = [
        ("sin filtro no toca nada", testInactiveFilterIsIdentity),
        ("busca por nombre en los dos idiomas", testSearchByName),
        ("ignora acentos y mayúsculas", testSearchIgnoresAccentsAndCase),
        ("busca por número de pokédex", testSearchByDexNumber),
        ("encuentra por la forma evolucionada", testSearchFindsEvolvedName),
        ("filtra por tipo", testFilterByType),
        ("filtra shiny, evolucionados y repetidos", testFlagFilters),
        ("filtra por generación", testFilterByGeneration),
        ("los cuatro órdenes colocan bien", testSortModes),
        ("filtrar nunca inventa ni duplica huecos", testFilterIsASubset),
    ]

    private static let dex = Pokedex.shared
    private static let evolution = EvolutionService()

    private static func captured(
        _ speciesID: Int,
        shiny: Bool = false,
        earned: Int = 0,
        secondsAgo: TimeInterval = 0
    ) -> CapturedPokemon {
        CapturedPokemon(
            speciesID: speciesID,
            isShiny: shiny,
            capturedAt: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            capturedAtTotalTokens: 0,
            evolutionSeed: 7,
            tokensEarned: earned
        )
    }

    /// Squirtle, dos Rattata, un Gastly shiny, un Cubone evolucionado a
    /// Marowak y un Chikorita de Gen 2.
    private static var sample: [BoxGroup] {
        BoxGroup.group(
            [
                captured(7, secondsAgo: 500),
                captured(19, secondsAgo: 400),
                captured(19, secondsAgo: 300),
                captured(92, shiny: true, secondsAgo: 200),
                captured(104, earned: 300_000, secondsAgo: 100),
                captured(152, secondsAgo: 0),
            ],
            pokedex: dex,
            evolution: evolution
        )
    }

    private static func ids(_ filter: BoxFilter) -> [Int] {
        filter.apply(to: sample).map(\.species.id)
    }

    static func testInactiveFilterIsIdentity() {
        let filter = BoxFilter()
        expectFalse(filter.isActive)
        expectEqual(ids(filter), [7, 19, 92, 104, 152], "orden Pokédex por defecto")
    }

    static func testSearchByName() {
        var filter = BoxFilter()
        filter.query = "rattata"
        expectEqual(ids(filter), [19])
        filter.query = "chiko"
        expectEqual(ids(filter), [152], "prefijo parcial")
        filter.query = "squirtle"
        expectEqual(ids(filter), [7], "nombre en inglés")
    }

    static func testSearchIgnoresAccentsAndCase() {
        var filter = BoxFilter()
        filter.query = "  RATTATA  "
        expectEqual(ids(filter), [19], "espacios y mayúsculas")
        // El nombre español de #83 lleva acento; comprobamos el plegado.
        expectEqual(BoxFilter.normalize("Marowak"), BoxFilter.normalize("márowák"))
    }

    static func testSearchByDexNumber() {
        var filter = BoxFilter()
        filter.query = "19"
        expectEqual(ids(filter), [19])
        filter.query = "#104"
        expectEqual(ids(filter), [104], "con almohadilla")
        filter.query = "007"
        expectEqual(ids(filter), [7], "con ceros por delante")
        filter.query = "999"
        expectEqual(ids(filter), [], "un número que no está no devuelve nada")
    }

    static func testSearchFindsEvolvedName() {
        var filter = BoxFilter()
        filter.query = "marowak"
        expectEqual(ids(filter), [104], "se busca también por cómo se ve ahora")
        filter.query = "cubone"
        expectEqual(ids(filter), [104], "y por la especie capturada")
    }

    static func testFilterByType() {
        var filter = BoxFilter()
        filter.types = ["water"]
        expectEqual(ids(filter), [7])
        filter.types = ["ghost", "grass"]
        expectEqual(ids(filter), [92, 152], "varios tipos suman")
    }

    static func testFlagFilters() {
        var filter = BoxFilter()
        filter.onlyShiny = true
        expectEqual(ids(filter), [92])

        filter = BoxFilter()
        filter.onlyEvolved = true
        expectEqual(ids(filter), [104])

        filter = BoxFilter()
        filter.onlyDuplicates = true
        expectEqual(ids(filter), [19], "solo el hueco con ×2")
    }

    static func testFilterByGeneration() {
        var filter = BoxFilter()
        filter.generation = 2
        expectEqual(ids(filter), [152, 104].filter { dex.require($0).generation == 2 })
        filter.generation = 1
        expectEqual(ids(filter), [7, 19, 92, 104])
    }

    static func testSortModes() {
        var filter = BoxFilter()
        filter.sort = .recent
        expectEqual(ids(filter).first, 152, "el último capturado primero")

        filter.sort = .count
        expectEqual(ids(filter).first, 19, "el ×2 primero")

        filter.sort = .rarity
        let rarities = filter.apply(to: sample).map(\.species.rarity.sortIndex)
        expectEqual(rarities, rarities.sorted(), "de lo más raro a lo más común")

        filter.sort = .dex
        expectEqual(ids(filter), [7, 19, 92, 104, 152])
    }

    static func testFilterIsASubset() {
        let all = sample
        var filter = BoxFilter()
        for query in ["a", "z", "19", "#", "", "rat", "no-existe"] {
            filter.query = query
            let result = filter.apply(to: all)
            expectTrue(result.count <= all.count, "'\(query)' devolvió más de lo que hay")
            expectEqual(Set(result.map(\.id)).count, result.count, "'\(query)' duplicó huecos")
            expectTrue(Set(result.map(\.id)).isSubset(of: Set(all.map(\.id))), "'\(query)' inventó huecos")
        }
    }
}
