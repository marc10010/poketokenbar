import Foundation
import PokeTokenBarCore

@MainActor
enum MilestoneTests: TestSuite {
    static let suiteName = "Hitos legendarios"

    static let tests: [(String, () throws -> Void)] = [
        ("el catálogo cubre a los 11 legendarios", testCatalogCoversEveryLegendary),
        ("cada hito vive en una zona que existe", testPlacesAreRealZones),
        ("los legendarios no aparecen en libertad", testLegendariesDoNotSpawn),
        ("el hito dice por qué no está disponible", testAvailabilityReasons),
        ("no se puede abrir con un gimnasio en curso", testCannotStartWhileBusy),
        ("al abrirlo desaparece el salvaje", testStartingReplacesTheWild),
        ("con el cruce bloqueado no baja el HP", testBlockedMilestone),
        ("al vencerlo SÍ se captura", testDefeatCapturesTheLegendary),
        ("se puede abandonar sin perder los salvajes", testAbandon),
        ("un cruce neutro no tumba a un legendario", testNeutralMatchupCannotWin),
    ]

    private static let catalog = MilestoneCatalog.shared
    private static let zones = ZoneCatalog.shared
    private static let dex = Pokedex.shared

    private static func makeStore(seed: UInt64 = 6) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func event(_ id: String, tokens: Int) -> UsageEvent {
        UsageEvent(id: id, inputTokens: tokens, outputTokens: 0)
    }

    /// Jugador con las 8 medallas de Johto, que es lo que abre la Torre Quemada.
    private static func withJohtoDone(seed: UInt64 = 6) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        return store
    }

    static func testCatalogCoversEveryLegendary() {
        let legendarios = Set(dex.all.filter(\.isLegendary).map(\.id))
        let conHito = Set(catalog.all.map(\.speciesID))
        expectEqual(conHito, legendarios, "sin hito: \(legendarios.subtracting(conHito).sorted())")
        expectEqual(catalog.all.count, 11)
        expectEqual(Set(catalog.all.map(\.id)).count, catalog.all.count, "ids únicos")
    }

    static func testPlacesAreRealZones() {
        for milestone in catalog.all {
            expectNotNil(zones[milestone.zoneID], "\(milestone.id) apunta a la zona \(milestone.zoneID)")
            expectTrue(dex[milestone.speciesID]?.isLegendary == true, "\(milestone.id) no es legendario")
            expectTrue(milestone.hpRange.lowerBound >= 1_500_000, "\(milestone.id) baja de 1,5M")
            expectTrue(milestone.hpRange.upperBound <= 4_000_000, "\(milestone.id) pasa de 4M")
            expectTrue(milestone.absorption >= 1, "\(milestone.id) absorbe menos que el último gimnasio")
        }
    }

    static func testLegendariesDoNotSpawn() {
        let spawner = SpawnService()
        let access = ZoneAccess(medals: 16, kantoOpen: true, isChampion: true)
        for rarity in Rarity.allCases where rarity.spawnsInTheWild {
            let pool = spawner.candidates(rarity: rarity, access: access)
            expectFalse(pool.contains(where: \.isLegendary), "\(rarity) ofrece legendarios")
        }
        var rng = SeededRandomProvider(seed: 3)
        for _ in 0..<3_000 {
            let encounter = spawner.spawn(rank: .campeon, access: access, using: &rng)
            expectFalse(dex[encounter.speciesID]?.isLegendary == true, "salió un legendario salvaje")
        }
    }

    static func testAvailabilityReasons() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)

        // Sin medallas, la Torre Quemada está cerrada.
        let raikou = try unwrap(catalog["torre-quemada-raikou"])
        if case .zoneClosed = store.availability(of: raikou) {} else {
            expectTrue(false, "esperaba zona cerrada, llegó \(store.availability(of: raikou).reason)")
        }

        store.debugDefeatGyms(upTo: 8)
        expectTrue(store.availability(of: raikou).isAvailable, "con Johto hecho ya se puede")

        // Ho-Oh pide 10 medallas por encima de su zona.
        let hooh = try unwrap(catalog["torre-campana-hooh"])
        expectEqual(store.availability(of: hooh), .needsMedals(2))

        // Mew pide Pokédex, no medallas.
        let mew = try unwrap(catalog["faraway-mew"])
        if case .needsSpecies = store.availability(of: mew) {} else if case .zoneClosed = store.availability(of: mew) {} else {
            expectTrue(false, "Mew debería pedir especies o su zona: \(store.availability(of: mew).reason)")
        }
    }

    /// Solo un jefe a la vez, por las dos vías: otro hito y un gimnasio.
    ///
    /// Ojo al orden: con 8 medallas el gimnasio siguiente ya es de Kanto y está
    /// tras la puerta de región, así que para tener un gimnasio en curso hay
    /// que abrir Kanto antes.
    static func testCannotStartWhileBusy() throws {
        let store = withJohtoDone()
        let raikou = try unwrap(catalog["torre-quemada-raikou"])
        let entei = try unwrap(catalog["torre-quemada-entei"])

        expectTrue(store.startMilestone(raikou.id))
        expectEqual(store.availability(of: entei), .busy)
        expectFalse(store.startMilestone(entei.id), "no se pueden abrir dos hitos")
        expectEqual(try unwrap(store.activeMilestone).milestone.id, raikou.id)
        store.abandonMilestone()

        // Ahora con un gimnasio en curso, que requiere Kanto abierta.
        store.debugWinLeague("johto")
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(event("abre-gim", tokens: 10))
        expectNotNil(store.activeGym, "con Kanto abierta sí hay gimnasio siguiente")
        expectEqual(store.availability(of: raikou), .busy)
        expectFalse(store.startMilestone(raikou.id))
        expectNil(store.activeMilestone)
    }

    static func testStartingReplacesTheWild() throws {
        let store = withJohtoDone()
        expectNotNil(store.state.encounter)
        expectTrue(store.startMilestone("torre-quemada-suicune"))

        let active = try unwrap(store.activeMilestone)
        expectEqual(active.milestone.speciesID, 245, "Suicune")
        expectNil(store.state.encounter, "no hay salvaje mientras se lucha el hito")
        expectTrue(active.milestone.hpRange.contains(active.battle.maxHP))
    }

    static func testBlockedMilestone() throws {
        let store = withJohtoDone(seed: 12)
        // Pikachu (eléctrico) contra Suicune (agua) es ×2... buscamos bloqueo
        // de verdad: Suicune absorbe 1,0 y un cruce ×0,5 no llega.
        store.debugCapture(speciesID: 133)          // Eevee, normal
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.startMilestone("torre-quemada-suicune"))
        let milestone = try unwrap(store.activeMilestone).milestone
        expectTrue(store.isBlocked(against: milestone), "normal contra agua no pasa la absorción")

        let before = try unwrap(store.activeMilestone).battle
        store.ingest(event("inútil", tokens: 500_000))
        let after = try unwrap(store.activeMilestone).battle
        expectEqual(after.currentHP, before.currentHP, "ni un HP")
        expectEqual(after.tokensSpent, before.tokensSpent + 500_000, "pero los tokens se gastaron")
        expectEqual(store.state.milestones.defeated, [], "y no hay legendario")
    }

    static func testDefeatCapturesTheLegendary() throws {
        // Squirtle (agua) contra Entei (fuego) es ×2, que contra absorción 1,0
        // deja 1,0 HP por token. Con cruce neutro sería imposible: ver el test
        // de abajo.
        let store = withJohtoDone(seed: 21)
        expectTrue(store.startMilestone("torre-quemada-entei"))
        let battle = try unwrap(store.activeMilestone).battle
        let boxBefore = store.state.box.count

        store.ingest(event("gana", tokens: battle.maxHP * 3))

        expectNil(store.activeMilestone, "el hito se cierra")
        expectEqual(store.state.milestones.defeated, ["torre-quemada-entei"])
        expectTrue(
            store.state.box.contains { $0.speciesID == 244 },
            "Entei entra en la caja: es la excepción a que un jefe no se queda"
        )
        expectGreaterThan(store.state.box.count, boxBefore)
        expectNotNil(store.state.encounter, "y vuelve a haber salvaje")

        // Y no se puede repetir.
        let entei = try unwrap(catalog["torre-quemada-entei"])
        expectEqual(store.availability(of: entei), .defeated)
        expectFalse(store.startMilestone(entei.id))
    }

    static func testAbandon() throws {
        let store = withJohtoDone(seed: 33)
        expectTrue(store.startMilestone("torre-quemada-raikou"))
        store.abandonMilestone()

        expectNil(store.activeMilestone)
        expectNotNil(store.state.encounter, "recupera sus salvajes")
        let raikou = try unwrap(catalog["torre-quemada-raikou"])
        expectTrue(store.availability(of: raikou).isAvailable, "y puede volver a intentarlo")
        expectEqual(store.state.milestones.defeated, [])
    }

    /// Propiedad del diseño: todos los hitos absorben 1,0 o más, así que con un
    /// cruce neutro el progreso es cero por muchos tokens que se gasten. Un
    /// legendario exige ventaja de tipo o etapa evolutiva, no paciencia.
    static func testNeutralMatchupCannotWin() throws {
        for milestone in catalog.all {
            expectTrue(
                milestone.absorption >= 1,
                "\(milestone.id) se podría ganar con cruce neutro"
            )
        }

        let store = withJohtoDone(seed: 42)
        store.updateSettings { $0.typeEffectivenessEnabled = false }   // todo neutro
        expectTrue(store.startMilestone("torre-quemada-entei"))
        let milestone = try unwrap(store.activeMilestone).milestone
        expectTrue(store.isBlocked(against: milestone))

        let hp = try unwrap(store.activeMilestone).battle.currentHP
        store.ingest(event("montaña-de-tokens", tokens: hp * 3))
        expectEqual(try unwrap(store.activeMilestone).battle.currentHP, hp, "no baja nada")
        expectEqual(store.state.milestones.defeated, [], "y no se consigue")
    }
}
