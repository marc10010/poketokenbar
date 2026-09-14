import Foundation
import PokeTokenBarCore

@MainActor
enum ZoneTests: TestSuite {
    static let suiteName = "Zonas"

    static let tests: [(String, () throws -> Void)] = [
        ("el catálogo cubre las 251 entre zonas y sin zona", testCoverage),
        ("las especies de una zona existen y son de Gen 1 o 2", testSpeciesAreReal),
        ("el desbloqueo va por medallas, región y campeón", testUnlockRules),
        ("la disponibilidad crece con el progreso y nunca baja", testAvailabilityGrows),
        ("no se puede cazar en una zona cerrada", testYouCannotHuntInAClosedZone),
        ("con cualquier progreso, la zona actual está abierta", testCurrentZoneIsAlwaysOpen),
        ("el tier de legendarios no se sortea con ningún rango", testLegendaryTierIsNeverRolled),
        ("sorteando de verdad, todo lo que sale vive donde estás", testSpawnStaysInsideTheZone),
        ("solo Mew se queda sin ruta ni precursor", testOnlyMewIsOrphan),
        ("lo que no tiene zona no se caza", testWhatHasNoZoneIsNotHuntable),
        ("una zona de una sola rareza reparte a partes iguales", testUniformInsideASingleTierZone),
        ("una zona no cuela legendarios ni formas evolucionadas", testZoneExcludesWhatNeverSpawns),
        ("no se puede ir a una zona cerrada", testMovingNeedsAnOpenZone),
        ("sin elegir, estás en la más profunda abierta", testDefaultsToTheDeepestOpenZone),
        ("la partida vieja conserva su zona", testLegacyFocusedZoneIsRead),
        ("la zona se persiste", testCurrentZonePersists),
    ]

    private static let catalog = ZoneCatalog.shared
    private static let dex = Pokedex.shared
    private static let spawner = SpawnService()

    private static func access(_ medals: Int, kanto: Bool = false, champion: Bool = false) -> ZoneAccess {
        ZoneAccess(
            medals: medals,
            openRegions: kanto ? Set(GymCatalog.shared.regions) : [GymCatalog.shared.regions.first ?? "kanto"],
            isChampion: champion
        )
    }

    private static func store(medals: Int = 16, kanto: Bool = true, champion: Bool = true) -> GameStore {
        let store = GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 21)
        )
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: min(medals, 8))
        if kanto { store.debugOpenRegion("kanto") }
        store.debugDefeatGyms(upTo: medals)
        if champion { store.debugWinLeague("kanto") }
        return store
    }

    /// Dentro de una zona con especies de una sola rareza el sorteo es
    /// uniforme, que es lo que hace legible el tamaño del bombo: en una zona
    /// de dos, lo que buscas sale una de cada dos.
    static func testUniformInsideASingleTierZone() throws {
        // Bosque Verde: Caterpie, Weedle y Pidgey, los tres comunes.
        let zone = try unwrap(catalog["bosque-verde"])
        let pool = spawner.pool(zone)
        expectGreaterThan(pool.count, 1)
        expectEqual(Set(pool.map(\.rarity)).count, 1, "el test necesita una zona de una sola rareza")

        var rng = SeededRandomProvider(seed: 99)
        var counts: [Int: Int] = [:]
        let rolls = 20_000
        for _ in 0..<rolls {
            counts[spawner.spawn(zone: zone, rank: .campeon, using: &rng).speciesID, default: 0] += 1
        }
        expectEqual(Set(counts.keys), Set(pool.map(\.id)), "solo salen las de la zona")
        let expected = Double(rolls) / Double(pool.count)
        for (id, count) in counts {
            let drift = abs(Double(count) - expected) / expected
            expectTrue(drift < 0.1, "#\(id) salió \(count) veces, se esperaba ~\(Int(expected))")
        }

        // Y todos aguantan lo mismo: la vida es de la zona.
        var local = SeededRandomProvider(seed: 5)
        for _ in 0..<200 {
            expectEqual(spawner.spawn(zone: zone, rank: .campeon, using: &local).maxHP, catalog.hp(of: zone))
        }
    }

    /// Enfocar no filtra por tipo ni por rareza —sale todo lo de la zona— pero
    /// lo que **nunca** aparece en libertad sigue sin aparecer: los legendarios
    /// son hitos, y un salvaje arranca su línea evolutiva.
    static func testZoneExcludesWhatNeverSpawns() throws {
        let electrica = try unwrap(catalog.all.first { $0.species.contains(145) })
        let pool = spawner.pool(electrica)
        expectTrue(!pool.contains { $0.id == 145 }, "Zapdos es un hito, no un salvaje")
        expectTrue(pool.allSatisfy { $0.isBaseForm }, "solo formas base")
        expectTrue(pool.allSatisfy { $0.rarity.spawnsInTheWild })

        // El rango sí gatea dentro de la zona: de novato, una zona con raras
        // no las da. La puerta de la zona dice dónde puedes ir; el rango, qué
        // se te pone delante cuando llegas.
        let withRare = try unwrap(catalog.all.first { zone in
            let pool = spawner.pool(zone)
            return pool.contains { $0.rarity == .rare } && pool.contains { $0.rarity != .rare }
        })
        var rng = SeededRandomProvider(seed: 4)
        var sawRare = false
        for _ in 0..<500 where spawner.spawn(zone: withRare, rank: .novato, using: &rng).rarity == .rare {
            sawRare = true
        }
        expectFalse(sawRare, "de novato no salen raros ni en su zona")
    }

    static func testMovingNeedsAnOpenZone() throws {
        let store = store(medals: 0, kanto: false, champion: false)
        let here = store.currentZone.id
        let closed = try unwrap(store.zoneCatalog.all.first { !store.zoneAccess.opens($0) })
        expectFalse(store.move(toZone: closed.id), "no se va a donde no está abierto")
        expectEqual(store.currentZone.id, here)

        let open = try unwrap(store.unlockedZones.first)
        expectTrue(store.move(toZone: open.id))
        expectEqual(store.currentZone.id, open.id)

        expectFalse(store.move(toZone: "no-existe"))
        expectEqual(store.currentZone.id, open.id, "un id inventado no cambia nada")
    }

    /// Sin haber elegido nunca, estás en la más profunda que tengas abierta:
    /// la frontera, que es donde se juega.
    static func testDefaultsToTheDeepestOpenZone() throws {
        let novato = store(medals: 0, kanto: false, champion: false)
        expectEqual(novato.currentZone.id, novato.deepestOpenZone.id)
        expectTrue(novato.zoneAccess.opens(novato.currentZone))

        let veterano = store(medals: 6, kanto: false, champion: false)
        expectGreaterThan(
            veterano.zoneDepth(veterano.currentZone),
            novato.zoneDepth(novato.currentZone),
            "con más medallas la frontera está más lejos"
        )
    }

    static func testCurrentZonePersists() throws {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let first = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 8))
        first.chooseStarter(speciesID: 7)
        let zone = try unwrap(first.unlockedZones.first)
        expectTrue(first.move(toZone: zone.id))
        first.flush()

        let reopened = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 8))
        expectEqual(reopened.currentZone.id, zone.id, "cazar algo concreto lleva sesiones")
    }

    /// La partida guardada con el nombre viejo del ajuste sigue valiendo.
    static func testLegacyFocusedZoneIsRead() throws {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let payload = #"{"schemaVersion":8,"settings":{"focusedZoneID":"bosque-verde"},"box":[],"ledger":{"total":0,"eventCount":0,"monthly":{}}}"#
        try Data(payload.utf8).write(to: url)
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 8))
        expectEqual(store.state.settings.currentZoneID, "bosque-verde")
    }

    static func testCoverage() {
        var covered = catalog.unassigned
        for zone in catalog.all { covered.formUnion(zone.species) }
        expectEqual(covered.count, 251, "faltan: \(Set(1...251).subtracting(covered).sorted())")
        expectGreaterThan(catalog.all.count, 20)
    }

    static func testSpeciesAreReal() {
        for zone in catalog.all {
            expectFalse(zone.species.isEmpty, "\(zone.id) sin especies")
            for id in zone.species {
                expectNotNil(dex[id], "\(zone.id) referencia #\(id), que no está en la Pokédex")
            }
            expectTrue(["johto", "kanto"].contains(zone.region), "\(zone.id): región \(zone.region)")
        }
    }

    static func testUnlockRules() throws {
        // Región 1 (Kanto): por medallas.
        let inicial = try unwrap(catalog["rutas-kanto-sur"])
        expectTrue(access(0).opens(inicial), "la zona inicial está abierta desde el principio")

        let central = try unwrap(catalog["central-electrica"])
        expectFalse(access(4).opens(central))
        expectTrue(access(5).opens(central), "la Central Eléctrica es de la región 1")

        // Región 2 (Johto): pide el barco, y algunas además medallas.
        let costa = try unwrap(catalog["rutas-johto-costa"])
        expectFalse(access(16).opens(costa), "sin Johto no se abre por muchas medallas que haya")
        expectFalse(access(11, kanto: true).opens(costa), "y con Johto necesita 12")
        expectTrue(access(12, kanto: true).opens(costa))

        let celeste = try unwrap(catalog["cueva-celeste"])
        expectFalse(access(16, kanto: true).opens(celeste), "Cueva Celeste es solo para el campeón")
        expectTrue(access(16, kanto: true, champion: true).opens(celeste))
    }

    static func testAvailabilityGrows() {
        let estados = [
            access(0),
            access(2),
            access(4),
            access(8),
            access(8, kanto: true),
            access(12, kanto: true),
            access(16, kanto: true, champion: true),
        ]
        var previo = Set<Int>()
        var previoCount = 0
        for estado in estados {
            let disponibles = catalog.availableSpecies(estado)
            expectTrue(previo.isSubset(of: disponibles), "abrir zonas nunca puede quitar especies")
            expectTrue(disponibles.count >= previoCount)
            previo = disponibles
            previoCount = disponibles.count
        }
        // Y la puerta significa algo: al principio no está ni la mitad.
        expectTrue(catalog.availableSpecies(access(0)).count < 100)
        expectGreaterThan(catalog.availableSpecies(access(16, kanto: true, champion: true)).count, 180)
    }

    /// Con la zona como bombo único, "no sale nada de una zona cerrada" deja
    /// de ser una propiedad del sorteo y pasa a ser una del sitio: no puedes
    /// estar allí. Es más fuerte y más fácil de comprobar.
    static func testYouCannotHuntInAClosedZone() throws {
        let store = store(medals: 14, kanto: true, champion: false)
        let helada = try unwrap(catalog["senda-helada"])
        expectFalse(store.zoneAccess.opens(helada), "con 14 medallas sigue cerrada")

        let antes = store.currentZone.id
        expectFalse(store.move(toZone: helada.id))
        expectEqual(store.currentZone.id, antes)

        // Y lo suyo propio no puede aparecer, porque no se sortea fuera de la
        // zona en la que estás.
        let exclusivos = Set(helada.species.filter { id in
            catalog.zones(for: id).allSatisfy { !store.zoneAccess.opens($0) }
        })
        expectGreaterThan(exclusivos.count, 0, "la zona debe aportar algo propio")
        var rng = SeededRandomProvider(seed: 4)
        for _ in 0..<2_000 {
            let wild = spawner.spawn(zone: store.currentZone, rank: store.rank, using: &rng)
            expectFalse(exclusivos.contains(wild.speciesID), "#\(wild.speciesID) sale con la Senda Helada cerrada")
        }
    }

    /// La forma general: con cualquier progreso, la zona en la que estás está
    /// abierta. Incluye el caso de la partida que aún no ha elegido.
    static func testCurrentZoneIsAlwaysOpen() {
        for medals in 0...16 {
            for kanto in [false, true] {
                let store = store(medals: medals, kanto: kanto, champion: false)
                expectTrue(
                    store.zoneAccess.opens(store.currentZone),
                    "con \(medals) medallas la zona actual está cerrada"
                )
            }
        }
    }

    /// El cortafuegos: por muchas medallas que tengas y en la zona que estés,
    /// el tier de legendarios no entra en el sorteo.
    static func testLegendaryTierIsNeverRolled() {
        for rank in TrainerRank.allCases {
            for zone in catalog.all {
                expectFalse(
                    spawner.availableTiers(rank: rank, in: zone).contains(.legendary),
                    "\(rank.label) puede sortear legendarios en \(zone.name)"
                )
            }
        }
    }

    /// Y por el camino que recorre la app: sorteando rivales de verdad, todo
    /// lo que sale vive donde estás.
    static func testSpawnStaysInsideTheZone() {
        var rng = SeededRandomProvider(seed: 4)
        for medals in [0, 2, 4, 8] {
            let store = store(medals: medals, kanto: false, champion: false)
            let vive = Set(spawner.pool(store.currentZone).map(\.id))
            for _ in 0..<3_000 {
                let encounter = spawner.spawn(zone: store.currentZone, rank: store.rank, using: &rng)
                expectTrue(
                    vive.contains(encounter.speciesID),
                    "#\(encounter.speciesID) aparece con \(medals) medallas fuera de \(store.currentZone.name)"
                )
            }
        }
    }

    static func testOnlyMewIsOrphan() {
        // Sin zona y sin precursor: no hay forma de conseguirlo salvo la red de
        // seguridad o un hito. Si esta lista crece, algo se rompió.
        let huerfanos = catalog.unassigned
            .compactMap { dex[$0] }
            .filter { $0.isBaseForm }
            .map(\.id)
            .sorted()
        expectEqual(huerfanos, [151], "solo Mew: \(huerfanos)")
    }

    /// Lo que no tiene zona no se caza: con el bombo global existía una red
    /// que las ofrecía en el tier más difícil, y con la zona como único bombo
    /// esa red no tiene dónde engancharse. No se pierde nada, porque de las 58
    /// sin zona la única forma base es Mew, que es un hito.
    static func testWhatHasNoZoneIsNotHuntable() {
        let sinZona = catalog.unassigned.compactMap { dex[$0] }
        expectTrue(
            sinZona.allSatisfy { !$0.isBaseForm || $0.isLegendary },
            "algo capturable se quedaría sin sitio donde salir"
        )
        for zone in catalog.all {
            let pool = Set(spawner.pool(zone).map(\.id))
            expectTrue(pool.isDisjoint(with: catalog.unassigned), "\(zone.name) ofrece algo sin zona")
        }
    }
}
