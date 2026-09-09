import Foundation
import PokeTokenBarCore

@MainActor
enum RegionTransferTests: TestSuite {
    static let suiteName = "Barco entre regiones"

    static let tests: [(String, () throws -> Void)] = [
        ("la liga sola no abre la región 2", testLeagueAloneIsNotEnough),
        ("solo cuentan las especies de la región 1", testOnlyPreviousRegionCounts),
        ("la última especie abre la región y se celebra", testLastSpeciesOpensTheRegion),
        ("el Alto Mando se puede ganar sin el requisito", testLeagueIsPlayableWithoutTheGate),
        ("a quien ya la tenía abierta no se le cierra", testGrandfatheredSavesKeepKanto),
        ("las zonas salen en orden de desbloqueo", testZonesAreOrderedByUnlock),
    ]

    private static let dex = Pokedex.shared

    private static func makeStore(seed: UInt64 = 12) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func kantoIDs(_ count: Int) -> [Int] {
        dex.all.filter { $0.homeRegion == "Kanto" }.map(\.id).sorted().prefix(count).map { $0 }
    }

    private static func ready(seed: UInt64 = 12) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        return store
    }

    static func testLeagueAloneIsNotEnough() throws {
        let store = ready()
        store.debugWinLeague("kanto")
        let transfer = try unwrap(store.transfer(to: "johto"))
        expectTrue(transfer.leagueWon)
        expectTrue(!transfer.isOpen, "falta la Pokédex")
        expectEqual(transfer.required, GameRules.regionTransferSpecies)
        expectEqual(transfer.missingSpecies, GameRules.regionTransferSpecies - transfer.registered)
        expectTrue(!store.openRegions.contains("johto"))
        expectEqual(store.nextGym, nil, "y el noveno gimnasio sigue esperando")
    }

    /// Antes de Kanto ya se ven 48 especies de Kanto en las rutas de Johto, así
    /// que contar cualquiera haría el requisito trivial.
    static func testOnlyPreviousRegionCounts() throws {
        let store = ready()
        store.debugWinLeague("kanto")
        for id in dex.all.filter({ $0.homeRegion == "Johto" }).prefix(90).map(\.id) {
            store.debugRegister(speciesID: id)
        }
        expectTrue(!store.openRegions.contains("johto"), "90 de Johto no valen para el barco")
        expectEqual(store.registeredSpecies(of: "kanto"), 1, "solo el inicial, Squirtle")

        for id in kantoIDs(GameRules.regionTransferSpecies) { store.debugRegister(speciesID: id) }
        expectTrue(store.openRegions.contains("johto"))
    }

    /// El requisito hace que el salto de región pueda llegar **en una captura**,
    /// no solo ganando un combate. Es el pago de coleccionar.
    static func testLastSpeciesOpensTheRegion() throws {
        let store = ready()
        store.debugWinLeague("kanto")
        let ids = kantoIDs(GameRules.regionTransferSpecies)
        for id in ids.dropLast() { store.debugRegister(speciesID: id) }
        store.flush()
        expectTrue(!store.openRegions.contains("johto"), "con una menos, no")
        expectEqual(store.lastRegion?.region, nil)

        store.debugRegister(speciesID: try unwrap(ids.last))
        store.flush()
        expectTrue(store.openRegions.contains("johto"))
        expectEqual(store.lastRegion?.region, "johto", "y se celebra")
        expectEqual(store.lastRegion?.registered, GameRules.regionTransferSpecies)

        store.dismissRegionCelebration()
        expectEqual(store.lastRegion?.region, nil)

        // Una sola vez: la fiesta no se repite en cada guardado.
        store.flush()
        expectEqual(store.lastRegion?.region, nil, "no se vuelve a celebrar")
    }

    static func testLeagueIsPlayableWithoutTheGate() throws {
        let store = ready()
        expectTrue(store.availability(of: try unwrap(store.leagueCatalog["kanto"])).isAvailable, "con 8 medallas se puede retar")
        expectTrue(store.startLeague("kanto"), "el requisito no bloquea el contenido, solo el barco")
    }

    /// K6: quitarle a alguien un acceso que ya tenía es peor que el problema
    /// que arregla el requisito.
    static func testGrandfatheredSavesKeepKanto() throws {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let legacy: [String: Any] = [
            "schemaVersion": 7,
            "box": [[
                "id": UUID().uuidString,
                "speciesID": 7,
                "isShiny": false,
                "capturedAt": "2026-09-01T10:00:00Z",
                "capturedAtTotalTokens": 0,
                "evolutionSeed": 3,
                "tokensEarned": 0,
            ]],
            "leagues": ["won": ["kanto"]],
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)

        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 3))
        expectTrue(store.state.grandfatheredRegions.contains("johto"))
        expectTrue(store.openRegions.contains("johto"), "ya la tenía abierta")
        expectTrue(store.registeredSpecies(of: "kanto") < GameRules.regionTransferSpecies, "y sin llegar al requisito")
        store.flush()
        expectEqual(store.lastRegion?.region, nil, "pero no se celebra algo de hace semanas")
    }

    static func testZonesAreOrderedByUnlock() {
        let order = ZoneCatalog.shared.inUnlockOrder
        expectEqual(Set(order.map(\.id)).count, ZoneCatalog.shared.all.count, "están todas y sin repetir")
        let keys = order.map { ($0.unlock.unlockOrder.0, $0.unlock.unlockOrder.1) }
        expectTrue(
            zip(keys, keys.dropFirst()).allSatisfy { $0 <= $1 },
            "primero Johto por medallas, luego Kanto, y al final las de Campeón: \(keys)"
        )
        expectEqual(order.first?.unlock.requiredMedals, 0)
        expectTrue(order.last?.unlock.requiresChampion == true)
    }
}
