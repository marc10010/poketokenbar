import Foundation
import PokeTokenBarCore

@MainActor
enum LeagueTests: TestSuite {
    static let suiteName = "Ligas y regiones"

    static let tests: [(String, () throws -> Void)] = [
        ("el catálogo tiene las dos ligas en orden", testCatalog),
        ("los gimnasios de la región 2 esperan al Alto Mando", testRegionGate),
        ("la liga pide medallas y la anterior", testAvailability),
        ("el gauntlet encadena miembros sin salvajes en medio", testGauntletChains),
        ("ganar la primera liga abre la segunda región", testFirstLeagueOpensSecondRegion),
        ("ganar Monte Plateado corona y abre Cueva Celeste", testChampionOpensCeruleanCave),
        ("abandonar reinicia la tirada", testAbandonResets),
        ("un miembro bloqueado detiene el gauntlet sin perderlo", testBlockedMemberStalls),
    ]

    private static let leagues = LeagueCatalog.shared
    private static let gyms = GymCatalog.shared
    private static let zones = ZoneCatalog.shared
    private static let dex = Pokedex.shared

    private static func makeStore(seed: UInt64 = 8) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func event(_ id: String, tokens: Int) -> UsageEvent {
        UsageEvent(id: id, inputTokens: tokens, outputTokens: 0)
    }

    /// Jugador con Johto hecho: 8 medallas y el Alto Mando disponible.
    private static func ready(seed: UInt64 = 8) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 8)
        return store
    }

    static func testCatalog() {
        // En orden de juego: primero el Alto Mando de Kanto, que abre Johto.
        expectEqual(leagues.all.map(\.id), ["kanto", "johto"])
        expectEqual(leagues.all.first?.members.count, 5, "Alto Mando de Kanto: cuatro y Blue")
        expectEqual(leagues.all.last?.members.count, 6, "el de Johto acaba con Red en el Monte Plateado")
        for league in leagues.all {
            expectEqual(league.members.map(\.order), Array(1...league.members.count))
            for member in league.members {
                expectNotNil(dex[member.signatureSpeciesID], "\(member.name) sin Pokémon")
                expectTrue(
                    member.absorption >= 1.5,
                    "\(member.name) absorbe menos que el último gimnasio"
                )
            }
        }
        expectEqual(leagues["kanto"]?.reward, .johto, "la primera abre la región 2")
        expectEqual(leagues["johto"]?.reward, .champion, "y la segunda da el título")
    }

    static func testRegionGate() throws {
        let store = ready()
        expectEqual(store.medals, 8)
        expectNil(store.nextGym, "el noveno es de la región 2 y está tras la puerta")
        expectEqual(store.gymGate?.id, "kanto", "y se dice qué lo bloquea: el Alto Mando de Kanto")

        store.debugOpenRegion("johto")
        let siguiente = try unwrap(store.nextGym)
        expectEqual(siguiente.region, "johto")
        expectEqual(siguiente.order, 9)
        expectNil(store.gymGate)
    }

    static func testAvailability() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        let primera = try unwrap(leagues["kanto"])     // Alto Mando de Kanto
        let segunda = try unwrap(leagues["johto"])     // Johto y el Monte Plateado

        expectEqual(store.availability(of: primera), .needsMedals(8))
        expectEqual(store.availability(of: segunda), .needsPreviousLeague(primera.name))

        store.debugDefeatGyms(upTo: 8)
        expectTrue(store.availability(of: primera).isAvailable)
        expectEqual(store.availability(of: segunda), .needsPreviousLeague(primera.name), "el orden manda")

        store.debugOpenRegion("johto")
        expectEqual(store.availability(of: primera), .won)
        expectEqual(store.availability(of: segunda), .needsMedals(8), "el final pide las 16")
    }

    static func testGauntletChains() throws {
        // Pikachu contra Lapras: eléctrico contra agua/hielo es ×2 y pasa la
        // absorción de 1,5 del primer miembro del Alto Mando.
        let store = ready(seed: 15)
        store.debugCapture(speciesID: 25)          // Pikachu: eléctrico
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.startLeague("kanto"))

        let primero = try unwrap(store.activeLeague)
        expectEqual(primero.member.name, "Lorelei")
        expectEqual(primero.run.memberIndex, 0)
        expectNil(store.state.encounter, "no hay salvaje durante la liga")

        // Eléctrico contra Lapras (agua/hielo) hace ×2 y pasa la absorción.
        expectFalse(store.isBlocked(against: primero.member))
        store.ingest(event("tumba-a-lorelei", tokens: primero.run.currentHP * 2))

        let segundo = try unwrap(store.activeLeague)
        expectEqual(segundo.run.memberIndex, 1, "encadena al siguiente")
        expectEqual(segundo.member.name, "Bruno")
        expectNil(store.state.encounter, "y sigue sin salvajes en medio")
        expectEqual(store.state.leagues.won, [], "todavía no está ganada")
    }

    /// Ganar el Alto Mando ya no basta: el barco pide además 70 especies de
    /// Kanto registradas, que es lo que hace que la región 1 haya que jugarla.
    static func testFirstLeagueOpensSecondRegion() throws {
        let store = ready(seed: 23)
        expectFalse(store.openRegions.contains("johto"))
        let costa = try unwrap(zones["rutas-johto-costa"])
        expectFalse(store.zoneAccess.opens(costa))

        store.debugWinLeague("kanto")
        expectFalse(store.openRegions.contains("johto"), "la liga sola no abre Johto")
        store.debugOpenRegion("johto")
        expectTrue(store.openRegions.contains("johto"))
        expectFalse(store.zoneAccess.opens(costa), "las rutas de la costa piden además 12 medallas")
        let rutas = try unwrap(zones["rutas-johto-sur"])
        expectTrue(store.zoneAccess.opens(rutas), "las rutas del sur de Johto sí se abren")
        expectGreaterThan(
            store.zoneCatalog.availableSpecies(store.zoneAccess).count,
            store.zoneCatalog.availableSpecies(ZoneAccess(medals: 8, openRegions: ["kanto"])).count
        )
    }

    static func testChampionOpensCeruleanCave() throws {
        let store = makeStore(seed: 31)
        store.chooseStarter(speciesID: 7)
        store.debugOpenRegion("johto")
        store.debugDefeatGyms(upTo: 16)
        expectFalse(store.zoneAccess.isChampion)

        let celeste = try unwrap(zones["cueva-celeste"])
        expectFalse(store.zoneAccess.opens(celeste))
        let mewtwo = try unwrap(MilestoneCatalog.shared["celeste-mewtwo"])
        if case .zoneClosed = store.availability(of: mewtwo) {} else {
            expectTrue(false, "Mewtwo debería estar tras su zona: \(store.availability(of: mewtwo).reason)")
        }

        store.debugWinLeague("johto")
        expectTrue(store.zoneAccess.isChampion)
        expectTrue(store.zoneAccess.opens(celeste))
        expectTrue(store.availability(of: mewtwo).isAvailable, "y Mewtwo ya se puede retar")
    }

    static func testAbandonResets() throws {
        let store = ready(seed: 44)
        store.debugCapture(speciesID: 25)          // Pikachu, ×2 contra Lapras
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.startLeague("kanto"))
        let hp = try unwrap(store.activeLeague).run.currentHP
        store.ingest(event("pega", tokens: hp / 2))
        expectTrue(try unwrap(store.activeLeague).run.currentHP < hp, "algo de daño sí hizo")

        store.abandonLeague()
        expectNil(store.activeLeague)
        expectNotNil(store.state.encounter, "recupera sus salvajes")

        // Y al volver empieza por el primero: es un gauntlet.
        expectTrue(store.startLeague("kanto"))
        let reinicio = try unwrap(store.activeLeague)
        expectEqual(reinicio.run.memberIndex, 0)
        expectEqual(reinicio.member.name, "Lorelei")
        expectEqual(reinicio.run.currentHP, reinicio.run.maxHP, "y a HP completo")
    }

    static func testBlockedMemberStalls() throws {
        let store = ready(seed: 52)
        store.updateSettings { $0.typeEffectivenessEnabled = false }   // todo neutro
        expectTrue(store.startLeague("kanto"))
        let member = try unwrap(store.activeLeague).member
        expectTrue(store.isBlocked(against: member), "neutro no pasa una absorción de 1,5")

        let before = try unwrap(store.activeLeague).run
        store.ingest(event("montaña", tokens: 5_000_000))
        let after = try unwrap(store.activeLeague).run
        expectEqual(after.currentHP, before.currentHP, "ni un HP")
        expectEqual(after.memberIndex, before.memberIndex, "no avanza")
        expectEqual(after.tokensSpent, before.tokensSpent + 5_000_000, "pero los tokens se gastan")
        expectEqual(store.state.leagues.won, [], "y no se gana por acumulación")
    }
}
