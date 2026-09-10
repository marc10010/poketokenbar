import Foundation
import PokeTokenBarCore

@MainActor
enum StarterTests: TestSuite {
    static let suiteName = "Iniciales por región"

    static let tests: [(String, () throws -> Void)] = [
        ("el inicial no se elige: lo da la región 1", testFirstRegionGivesItsStarter),
        ("abrir la región 2 trae su inicial", testOpeningARegionBringsItsStarter),
        ("no duplica una línea que ya tienes", testNeverDuplicatesALineYouOwn),
        ("reiniciar lo repone", testResetGivesItBack),
    ]

    private static let dex = Pokedex.shared

    private static func makeStore(seed: UInt64 = 77) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func lines(_ store: GameStore) -> Set<Int> {
        Set(store.state.box.compactMap { dex[$0.speciesID]?.baseFormID })
    }

    static func testFirstRegionGivesItsStarter() throws {
        let store = makeStore()
        expectTrue(store.state.box.isEmpty, "de fábrica no hay nada")

        let nuevos = store.ensureStarters()
        expectEqual(nuevos.count, 1, "solo el de la región abierta")
        expectEqual(nuevos.first?.speciesID, 4, "Charmander, el de Kanto")
        expectEqual(store.activeForm?.id, 4, "y queda equipado")
        expectNotNil(store.state.encounter, "con su primer rival delante")
        expectTrue(store.state.registeredSpeciesIDs.contains(4), "y en la Pokédex")

        // El de Johto no llega hasta abrir Johto: es la región 2.
        expectTrue(!lines(store).contains(155), "Cyndaquil todavía no")
        expectEqual(store.ensureStarters().count, 0, "y llamarlo otra vez no regala nada")
    }

    static func testOpeningARegionBringsItsStarter() throws {
        let store = makeStore()
        store.ensureStarters()
        store.debugGrandfatherRegion("johto")
        store.flush()      // la apertura se apunta al guardar

        expectTrue(lines(store).contains(155), "abrir Johto trae a Cyndaquil")
        expectEqual(store.state.box.count, 2, "uno por región abierta")
        expectEqual(store.activeForm?.id, 4, "sin cambiarte el compañero")
    }

    /// Tu partida: arrancó cuando Johto era la región 1, así que ya tienes su
    /// línea. Abrir Johto no te da un segundo Cyndaquil.
    static func testNeverDuplicatesALineYouOwn() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 155)         // Cyndaquil, de la vieja usanza
        let nuevos = store.ensureStarters()
        expectEqual(nuevos.count, 1, "le falta el de Kanto")
        expectEqual(nuevos.first?.speciesID, 4)

        store.debugGrandfatherRegion("johto")
        store.flush()
        expectEqual(store.state.box.filter { $0.speciesID == 155 }.count, 1, "un solo Cyndaquil")
        expectEqual(store.state.box.count, 2)
    }

    static func testResetGivesItBack() throws {
        let store = makeStore()
        store.ensureStarters()
        store.debugCapture(speciesID: 19)
        store.resetGame()

        expectEqual(store.state.box.count, 1, "la caja queda con el inicial y nada más")
        expectEqual(store.state.box.first?.speciesID, 4)
        expectEqual(store.medals, 0)
        expectEqual(store.totalTokens, 0)
    }
}
