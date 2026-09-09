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

    /// Jugador con las 8 medallas de la región 1, que es lo que abre los
    /// primeros hitos: los tres pájaros de Kanto (Central Eléctrica, Islas
    /// Espuma y Calle Victoria) piden 8 medallas por encima de sus zonas.
    private static func withRegionOneDone(seed: UInt64 = 6) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        return store
    }

    /// Y con la región 2 abierta y sus 16 medallas, que es lo que abre los de
    /// Johto (Torre Quemada, Torre Campana, Islas Remolino).
    private static func withEverythingButChampion(seed: UInt64 = 6) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        store.debugOpenRegion("johto")
        store.debugDefeatGyms(upTo: 16)
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
        let access = ZoneAccess(medals: 16, openRegions: Set(GymCatalog.shared.regions), isChampion: true)
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

        // Sin medallas, la Central Eléctrica está cerrada.
        let zapdos = try unwrap(catalog["central-zapdos"])
        if case .zoneClosed = store.availability(of: zapdos) {} else {
            expectTrue(false, "esperaba zona cerrada, llegó \(store.availability(of: zapdos).reason)")
        }

        // Con 5 medallas la zona abre, pero el hito pide 8.
        store.debugDefeatGyms(upTo: 5)
        expectEqual(store.availability(of: zapdos), .needsMedals(3))

        store.debugDefeatGyms(upTo: 8)
        expectTrue(store.availability(of: zapdos).isAvailable, "con la región 1 hecha ya se puede")

        // Y los de Johto siguen esperando al barco.
        let raikou = try unwrap(catalog["torre-quemada-raikou"])
        if case .zoneClosed = store.availability(of: raikou) {} else {
            expectTrue(false, "Raikou espera a Johto: \(store.availability(of: raikou).reason)")
        }

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
    /// Con 8 medallas y la región 2 abierta hay a la vez dos hitos de Kanto
    /// disponibles y un gimnasio de Johto al que entrar, que es lo que este
    /// test necesita. Con las 16 medallas no quedaría ningún gimnasio.
    static func testCannotStartWhileBusy() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        store.debugOpenRegion("johto")
        let raikou = try unwrap(catalog["central-zapdos"])
        let entei = try unwrap(catalog["espuma-articuno"])

        expectTrue(store.startMilestone(raikou.id))
        expectEqual(store.availability(of: entei), .busy)
        expectFalse(store.startMilestone(entei.id), "no se pueden abrir dos hitos")
        expectEqual(try unwrap(store.activeMilestone).milestone.id, raikou.id)
        store.abandonMilestone()

        // Ahora con un gimnasio en curso.
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(event("abre-gim", tokens: 10))
        // El gimnasio queda disponible y hay que entrar: es opcional.
        let disponible = try unwrap(store.availableGym)
        expectTrue(store.startGym(disponible.id))
        expectNotNil(store.activeGym, "hay gimnasio al que entrar")
        expectEqual(store.availability(of: raikou), .busy)
        expectFalse(store.startMilestone(raikou.id))
        expectNil(store.activeMilestone)
    }

    static func testStartingReplacesTheWild() throws {
        let store = withEverythingButChampion()
        expectNotNil(store.state.encounter)
        expectTrue(store.startMilestone("torre-quemada-suicune"))

        let active = try unwrap(store.activeMilestone)
        expectEqual(active.milestone.speciesID, 245, "Suicune")
        expectNil(store.state.encounter, "no hay salvaje mientras se lucha el hito")
        expectTrue(active.milestone.hpRange.contains(active.battle.maxHP))
    }

    static func testBlockedMilestone() throws {
        let store = withEverythingButChampion(seed: 12)
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
        let store = withEverythingButChampion(seed: 21)
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
        let store = withEverythingButChampion(seed: 33)
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

        let store = withEverythingButChampion(seed: 42)
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
