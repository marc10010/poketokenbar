import Foundation
import PokeTokenBarCore

@MainActor
enum LeagueTests: TestSuite {
    static let suiteName = "Ligas y regiones"

    static let tests: [(String, () throws -> Void)] = [
        ("el catálogo tiene las dos ligas en orden", testCatalog),
        ("los gimnasios de Kanto esperan al Alto Mando", testRegionGate),
        ("la liga pide medallas y la anterior", testAvailability),
        ("el gauntlet encadena miembros sin salvajes en medio", testGauntletChains),
        ("ganar Johto abre Kanto y sus zonas", testJohtoOpensKanto),
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
        expectEqual(leagues.all.map(\.id), ["johto", "kanto"])
        expectEqual(leagues.all.first?.members.count, 5, "Alto Mando: cuatro y campeón")
        expectEqual(leagues.all.last?.members.count, 1, "Monte Plateado: solo Red")
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
        expectEqual(leagues["johto"]?.reward, .kanto)
        expectEqual(leagues["kanto"]?.reward, .champion)
    }

    static func testRegionGate() throws {
        let store = ready()
        expectEqual(store.medals, 8)
        expectNil(store.nextGym, "el noveno es de Kanto y está tras la puerta")
        expectEqual(store.gymGate?.id, "johto", "y se dice qué lo bloquea")

        store.debugOpenRegion("kanto")
        let siguiente = try unwrap(store.nextGym)
        expectEqual(siguiente.region, "kanto")
        expectEqual(siguiente.order, 9)
        expectNil(store.gymGate)
    }

    static func testAvailability() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        let johto = try unwrap(leagues["johto"])
        let kanto = try unwrap(leagues["kanto"])

        expectEqual(store.availability(of: johto), .needsMedals(8))
        expectEqual(store.availability(of: kanto), .needsPreviousLeague(johto.name))

        store.debugDefeatGyms(upTo: 8)
        expectTrue(store.availability(of: johto).isAvailable)
        expectEqual(store.availability(of: kanto), .needsPreviousLeague(johto.name), "el orden manda")

        store.debugOpenRegion("kanto")
        expectEqual(store.availability(of: johto), .won)
        expectEqual(store.availability(of: kanto), .needsMedals(8), "Red pide las 16")
    }

    static func testGauntletChains() throws {
        // Onix SIN tokens ganados: roca contra Xatu (psíquico/volador) es ×2 y
        // pasa la absorción de 1,5. Con tokens ganados evolucionaría a Steelix
        // y el acero contra psíquico/volador es ×1, o sea bloqueado: los tipos
        // que cuentan son los de la forma que se muestra, no los de la
        // capturada.
        let store = ready(seed: 15)
        store.debugCapture(speciesID: 95)
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.startLeague("johto"))

        let primero = try unwrap(store.activeLeague)
        expectEqual(primero.member.name, "Will")
        expectEqual(primero.run.memberIndex, 0)
        expectNil(store.state.encounter, "no hay salvaje durante la liga")

        // Onix es roca/tierra: contra Xatu (psíquico/volador) roca hace ×2.
        expectFalse(store.isBlocked(against: primero.member))
        store.ingest(event("tumba-a-will", tokens: primero.run.currentHP * 2))

        let segundo = try unwrap(store.activeLeague)
        expectEqual(segundo.run.memberIndex, 1, "encadena al siguiente")
        expectEqual(segundo.member.name, "Koga")
        expectNil(store.state.encounter, "y sigue sin salvajes en medio")
        expectEqual(store.state.leagues.won, [], "todavía no está ganada")
    }

    /// Ganar el Alto Mando ya no basta: el barco pide además 50 especies de
    /// Johto registradas, que es lo que hace que la región 1 haya que jugarla.
    static func testJohtoOpensKanto() throws {
        let store = ready(seed: 23)
        expectFalse(store.zoneAccess.kantoOpen)
        let central = try unwrap(zones["central-electrica"])
        expectFalse(store.zoneAccess.opens(central))

        store.debugWinLeague("johto")
        expectFalse(store.zoneAccess.kantoOpen, "la liga sola no abre Kanto")
        store.debugOpenRegion("kanto")
        expectTrue(store.zoneAccess.kantoOpen)
        expectTrue(store.zoneAccess.opens(central) == false, "la Central pide además 12 medallas")
        let rutas = try unwrap(zones["rutas-kanto-sur"])
        expectTrue(store.zoneAccess.opens(rutas), "las rutas de Kanto sí se abren")
        expectGreaterThan(
            store.zoneCatalog.availableSpecies(store.zoneAccess).count,
            store.zoneCatalog.availableSpecies(ZoneAccess(medals: 8, kantoOpen: false, isChampion: false)).count
        )
    }

    static func testChampionOpensCeruleanCave() throws {
        let store = makeStore(seed: 31)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 16)
        store.debugOpenRegion("kanto")
        expectFalse(store.zoneAccess.isChampion)

        let celeste = try unwrap(zones["cueva-celeste"])
        expectFalse(store.zoneAccess.opens(celeste))
        let mewtwo = try unwrap(MilestoneCatalog.shared["celeste-mewtwo"])
        if case .zoneClosed = store.availability(of: mewtwo) {} else {
            expectTrue(false, "Mewtwo debería estar tras su zona: \(store.availability(of: mewtwo).reason)")
        }

        store.debugWinLeague("kanto")
        expectTrue(store.zoneAccess.isChampion)
        expectTrue(store.zoneAccess.opens(celeste))
        expectTrue(store.availability(of: mewtwo).isAvailable, "y Mewtwo ya se puede retar")
    }

    static func testAbandonResets() throws {
        let store = ready(seed: 44)
        store.debugCapture(speciesID: 95)          // Onix, ×2 contra Xatu
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.startLeague("johto"))
        let hp = try unwrap(store.activeLeague).run.currentHP
        store.ingest(event("pega", tokens: hp / 2))
        expectTrue(try unwrap(store.activeLeague).run.currentHP < hp, "algo de daño sí hizo")

        store.abandonLeague()
        expectNil(store.activeLeague)
        expectNotNil(store.state.encounter, "recupera sus salvajes")

        // Y al volver empieza por el primero: es un gauntlet.
        expectTrue(store.startLeague("johto"))
        let reinicio = try unwrap(store.activeLeague)
        expectEqual(reinicio.run.memberIndex, 0)
        expectEqual(reinicio.member.name, "Will")
        expectEqual(reinicio.run.currentHP, reinicio.run.maxHP, "y a HP completo")
    }

    static func testBlockedMemberStalls() throws {
        let store = ready(seed: 52)
        store.updateSettings { $0.typeEffectivenessEnabled = false }   // todo neutro
        expectTrue(store.startLeague("johto"))
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
