import Foundation
import PokeTokenBarCore

@MainActor
enum BoxSectionTests: TestSuite {
    static let suiteName = "BoxSection"

    static let tests: [(String, () throws -> Void)] = [
        ("los tramos no pierden ni reordenan huecos", testSectionsPreserveEverything),
        ("cada etiqueta sale una sola vez con los cuatro órdenes", testSectionsAreContiguous),
        ("las cabeceras dicen lo que ordena", testSectionTitlesMatchTheSort),
        ("las flechas cruzan de tramo", testMoveCrossesSections),
        ("subir conserva la columna", testMoveUpKeepsColumn),
        ("en los extremos no se sale", testMoveClampsAtTheEdges),
        ("sin selección empieza por el primero", testMoveWithoutSelection),
        ("barriendo a la derecha se visitan todos", testSweepVisitsEveryGroup),
        ("una columna deja la caja en lista", testSingleColumn),
        ("el teclado no sale de lo filtrado", testKeyboardStaysInsideTheFilter),
        ("intro equipa el seleccionado", testReturnEquipsSelection),
        ("la densidad se persiste", testDensitySurvivesReload),
    ]

    private static let dex = Pokedex.shared
    private static let evolution = EvolutionService()

    private static func captured(_ speciesID: Int, shiny: Bool = false, earned: Int = 0, secondsAgo: TimeInterval = 0) -> CapturedPokemon {
        CapturedPokemon(
            speciesID: speciesID,
            isShiny: shiny,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 - secondsAgo),
            capturedAtTotalTokens: 0,
            evolutionSeed: 7,
            tokensEarned: earned
        )
    }

    /// Gen 1 y Gen 2 mezcladas, un legendario, un shiny y un evolucionado.
    private static var sample: [BoxGroup] {
        BoxGroup.group(
            [
                captured(7, secondsAgo: 90 * 86_400),
                captured(19, secondsAgo: 60 * 86_400),
                captured(92, shiny: true, secondsAgo: 30 * 86_400),
                captured(104, earned: 300_000, secondsAgo: 20 * 86_400),
                captured(150, secondsAgo: 10 * 86_400),
                captured(152, secondsAgo: 5 * 86_400),
                captured(179, secondsAgo: 0),
            ],
            pokedex: dex,
            evolution: evolution
        )
    }

    private static func sections(_ sort: BoxFilter.Sort, wins: [Int: Int] = [:]) -> [BoxSection] {
        var filter = BoxFilter()
        filter.sort = sort
        let groups = filter.apply(to: sample) { wins[$0] ?? 0 }
        return BoxSection.build(groups, sort: sort) { wins[$0] ?? 0 }
    }

    private static func flat(_ sections: [BoxSection]) -> [String] {
        sections.flatMap { $0.groups.map(\.id) }
    }

    /// Partir en tramos es solo dibujar: si perdiera un hueco, la caja
    /// enseñaría menos de lo que tienes sin decirlo.
    static func testSectionsPreserveEverything() {
        for sort in BoxFilter.Sort.allCases {
            var filter = BoxFilter()
            filter.sort = sort
            let expected = filter.apply(to: sample).map(\.id)
            expectEqual(flat(sections(sort)), expected, "orden \(sort.label)")
        }
    }

    /// Con los cuatro órdenes los tramos salen contiguos, así que ninguna
    /// etiqueta se repite. Si un orden nuevo intercalara claves, este test
    /// avisa antes de que la caja muestre "Generación 1" dos veces.
    static func testSectionsAreContiguous() {
        for sort in BoxFilter.Sort.allCases {
            let titles = sections(sort, wins: [19: 3, 92: 40]).map(\.title)
            expectEqual(Set(titles).count, titles.count, "orden \(sort.label) fragmentó tramos")
        }
    }

    static func testSectionTitlesMatchTheSort() {
        expectEqual(sections(.dex).map(\.title), ["Generación 1", "Generación 2"])
        expectEqual(sections(.rarity).first?.title, "Legendario", "primero lo más raro")

        let byWins = sections(.wins, wins: [92: 40, 19: 3])
        expectEqual(byWins.map(\.title), ["20 victorias o más", "De 1 a 4 victorias", "Sin victorias contra su línea"])

        // El mes se escribe en castellano y con el año, que es lo que
        // distingue dos septiembres.
        expectEqual(BoxSection.monthLabel("2026-09"), "Septiembre de 2026")
        expectEqual(BoxSection.monthLabel("basura"), "basura", "una clave rara se enseña tal cual")
    }

    static func testMoveCrossesSections() throws {
        let sections = sections(.dex)
        expectEqual(sections.count, 2)
        let lastOfFirst = try unwrap(sections[0].groups.last?.id)
        let firstOfSecond = try unwrap(sections[1].groups.first?.id)

        expectEqual(BoxSection.move(.right, from: lastOfFirst, in: sections, columns: 4), firstOfSecond)
        expectEqual(BoxSection.move(.left, from: firstOfSecond, in: sections, columns: 4), lastOfFirst)
        // Bajar desde la última fila de un tramo entra en el siguiente.
        expectEqual(BoxSection.move(.down, from: lastOfFirst, in: sections, columns: 4), firstOfSecond)
    }

    /// Cada tramo empieza fila nueva, así que subir tiene que caer en la
    /// última fila del anterior y en la misma columna, no en su primer hueco.
    static func testMoveUpKeepsColumn() throws {
        let sections = sections(.dex)
        let first = sections[0].groups
        let second = sections[1].groups
        expectEqual(first.count, 5, "Gen 1: Squirtle, Rattata, Gastly, Marowak y Mewtwo")
        expectEqual(second.count, 2, "Gen 2: Chikorita y Teddiursa")

        // Con 2 columnas, Gen 1 ocupa 3 filas: [0,1] [2,3] [4].
        let secondColumnOfGen2 = try unwrap(second.last?.id)
        expectEqual(
            BoxSection.move(.up, from: secondColumnOfGen2, in: sections, columns: 2),
            first[4].id,
            "la última fila de Gen 1 solo tiene la columna 0"
        )
        expectEqual(
            BoxSection.move(.up, from: second[0].id, in: sections, columns: 2),
            first[4].id
        )
        expectEqual(BoxSection.move(.up, from: first[2].id, in: sections, columns: 2), first[0].id)
    }

    static func testMoveClampsAtTheEdges() throws {
        let sections = sections(.dex)
        let firstID = try unwrap(sections.first?.groups.first?.id)
        let lastID = try unwrap(sections.last?.groups.last?.id)

        expectEqual(BoxSection.move(.left, from: firstID, in: sections, columns: 4), firstID)
        expectEqual(BoxSection.move(.up, from: firstID, in: sections, columns: 4), firstID)
        expectEqual(BoxSection.move(.right, from: lastID, in: sections, columns: 4), lastID)
        expectEqual(BoxSection.move(.down, from: lastID, in: sections, columns: 4), lastID)
        expectEqual(BoxSection.move(.right, from: "no-existe", in: sections, columns: 4), firstID, "una selección muerta vuelve al principio")
        expectEqual(BoxSection.move(.right, from: firstID, in: [], columns: 4), nil, "sin tramos no hay a dónde ir")
    }

    static func testMoveWithoutSelection() throws {
        let sections = sections(.dex)
        let firstID = try unwrap(sections.first?.groups.first?.id)
        for direction in [BoxMove.left, .right, .up, .down] {
            expectEqual(BoxSection.move(direction, from: nil, in: sections, columns: 3), firstID)
        }
    }

    /// El recorrido completo con una sola tecla es lo que hace navegable una
    /// caja de doscientos huecos.
    static func testSweepVisitsEveryGroup() throws {
        let sections = sections(.dex)
        let all = flat(sections)
        var visited: [String] = []
        var current = try unwrap(BoxSection.move(.right, from: nil, in: sections, columns: 4))
        visited.append(current)
        while visited.count < all.count * 2 {
            let next = try unwrap(BoxSection.move(.right, from: current, in: sections, columns: 4))
            if next == current { break }
            current = next
            visited.append(next)
        }
        expectEqual(visited, all, "de izquierda a derecha se visitan todos y en orden")
    }

    static func testSingleColumn() throws {
        let sections = sections(.dex)
        let first = sections[0].groups
        // columns: 0 no puede dividir por cero ni congelar la selección.
        expectEqual(BoxSection.move(.down, from: first[0].id, in: sections, columns: 0), first[1].id)
        expectEqual(BoxSection.move(.up, from: first[1].id, in: sections, columns: 1), first[0].id)
    }

    private static func primedStore() -> GameStore {
        let store = GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 11)
        )
        store.chooseStarter(speciesID: 7)
        store.debugCapture(speciesID: 19)
        store.debugCapture(speciesID: 152)
        return store
    }

    /// Mover la selección con un filtro puesto no puede seleccionar algo que
    /// no se ve: sería equipar a ciegas.
    static func testKeyboardStaysInsideTheFilter() throws {
        let store = primedStore()
        store.boxFilter.generation = 2
        let visible = Set(store.filteredBoxGroups.map(\.id))
        expectEqual(visible.count, 1, "solo Chikorita es de Gen 2")

        for direction in [BoxMove.right, .down, .left, .up] {
            let moved = try unwrap(store.moveBoxSelection(direction, columns: 3))
            expectTrue(visible.contains(moved), "seleccionó \(moved), que está filtrado")
        }
    }

    static func testReturnEquipsSelection() throws {
        let store = primedStore()
        expectTrue(!store.sendSelectedToBattle(), "sin selección no equipa nada")

        let target = try unwrap(store.boxGroups.first { $0.id != store.activeGroupID })
        store.selectedBoxGroupID = target.id
        expectTrue(store.sendSelectedToBattle())
        expectEqual(store.activeGroupID, target.id)

        store.selectedBoxGroupID = "no-existe"
        expectTrue(!store.sendSelectedToBattle(), "una selección muerta no cambia de compañero")
        expectEqual(store.activeGroupID, target.id)
    }

    /// La densidad es preferencia de lectura, así que se persiste; el filtro
    /// no, porque arrancar con una búsqueda puesta desconcierta.
    static func testDensitySurvivesReload() {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 3))
        store.chooseStarter(speciesID: 7)
        store.updateSettings { $0.boxDensity = .lista }
        store.boxFilter.query = "rat"
        // El guardado va en diferido; sin esto se leería el fichero anterior.
        store.flush()

        let reopened = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 3))
        expectEqual(reopened.state.settings.boxDensity, .lista)
        expectEqual(reopened.boxFilter.query, "", "el filtro no se persiste")
    }
}
