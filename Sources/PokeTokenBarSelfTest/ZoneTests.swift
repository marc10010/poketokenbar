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
        ("una zona cerrada no ofrece sus especies", testClosedZoneIsNotOffered),
        ("con cualquier progreso, nada sale de una zona cerrada", testNothingLeaksFromClosedZones),
        ("el tier de legendarios no se sortea con ningún rango", testLegendaryTierIsNeverRolled),
        ("sorteando de verdad tampoco se cuela nada cerrado", testSpawnStaysInsideOpenZones),
        ("solo Mew se queda sin ruta ni precursor", testOnlyMewIsOrphan),
        ("lo que no tiene zona se ofrece en el tier más difícil", testFallbackTier),
        ("ningún tier se queda sin candidatas", testNoTierEverStarves),
        ("la zona enfocada saca todo lo suyo a partes iguales", testFocusIsUniformOverTheZone),
        ("enfocar no cuela legendarios ni formas evolucionadas", testFocusExcludesWhatNeverSpawns),
        ("una zona cerrada no se puede enfocar", testFocusNeedsAnOpenZone),
        ("el enfoque se persiste y se puede quitar", testFocusPersists),
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

    /// Lo que hace que la mecánica no tenga constantes que ajustar: la
    /// probabilidad de una especie concreta **es** el tamaño de la zona.
    static func testFocusIsUniformOverTheZone() throws {
        let zone = try unwrap(catalog["guarida-dragon"] ?? catalog.all.first { spawner.focusPool($0).count == 2 })
        let pool = spawner.focusPool(zone)
        expectGreaterThan(pool.count, 1)

        var rng = SeededRandomProvider(seed: 99)
        var counts: [Int: Int] = [:]
        let rolls = 20_000
        for _ in 0..<rolls {
            let wild = spawner.spawn(
                rank: .campeon,
                access: access(16, kanto: true, champion: true),
                focus: zone,
                using: &rng
            )
            counts[wild.speciesID, default: 0] += 1
        }
        expectEqual(Set(counts.keys), Set(pool.map(\.id)), "solo salen las de la zona")
        let expected = Double(rolls) / Double(pool.count)
        for (id, count) in counts {
            let drift = abs(Double(count) - expected) / expected
            expectTrue(drift < 0.1, "#\(id) salió \(count) veces, se esperaba ~\(Int(expected))")
        }

        // Y el HP sale de la rareza de la especie, no del tier sorteado.
        for (id, _) in counts {
            let species = dex.require(id)
            var local = SeededRandomProvider(seed: 5)
            let wild = spawner.spawn(rank: .novato, access: access(16, kanto: true, champion: true), focus: zone, using: &local)
            if wild.speciesID == id {
                expectTrue(species.rarity.hpRange.contains(wild.maxHP), "HP fuera del rango de \(species.name)")
            }
        }
    }

    /// Enfocar no filtra por tipo ni por rareza —sale todo lo de la zona— pero
    /// lo que **nunca** aparece en libertad sigue sin aparecer: los legendarios
    /// son hitos, y un salvaje arranca su línea evolutiva.
    static func testFocusExcludesWhatNeverSpawns() throws {
        let electrica = try unwrap(catalog.all.first { $0.species.contains(145) })
        let pool = spawner.focusPool(electrica)
        expectTrue(!pool.contains { $0.id == 145 }, "Zapdos es un hito, no un salvaje")
        expectTrue(pool.allSatisfy { $0.isBaseForm }, "solo formas base")
        expectTrue(pool.allSatisfy { $0.rarity.spawnsInTheWild })

        // Pero sin filtro de rango: una zona con raras las da igual de novato.
        let withRare = try unwrap(catalog.all.first { zone in
            spawner.focusPool(zone).contains { $0.rarity == .rare } && spawner.focusPool(zone).count <= 3
        })
        var rng = SeededRandomProvider(seed: 4)
        var sawRare = false
        for _ in 0..<200 {
            let wild = spawner.spawn(rank: .novato, access: access(16, kanto: true, champion: true), focus: withRare, using: &rng)
            if wild.rarity == .rare { sawRare = true }
        }
        expectTrue(sawRare, "enfocar no filtra por rareza: el rango no gatea la zona")
    }

    static func testFocusNeedsAnOpenZone() throws {
        let store = store(medals: 0, kanto: false, champion: false)
        let closed = try unwrap(store.zoneCatalog.all.first { !store.zoneAccess.opens($0) })
        store.focus(zoneID: closed.id)
        expectEqual(store.focusedZone, nil, "no se enfoca lo que no está abierto")

        let open = try unwrap(store.unlockedZones.first)
        store.focus(zoneID: open.id)
        expectEqual(store.focusedZone?.id, open.id)

        store.focus(zoneID: "no-existe")
        expectEqual(store.focusedZone?.id, open.id, "un id inventado no cambia nada")
    }

    static func testFocusPersists() throws {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let first = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 8))
        first.chooseStarter(speciesID: 7)
        let zone = try unwrap(first.unlockedZones.first)
        first.focus(zoneID: zone.id)
        first.flush()

        let reopened = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 8))
        expectEqual(reopened.focusedZone?.id, zone.id, "cazar algo concreto lleva sesiones")
        reopened.focus(zoneID: nil)
        expectEqual(reopened.focusedZone, nil)
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

    static func testClosedZoneIsNotOffered() throws {
        // Los de la Senda Helada no pueden salir antes de abrirla, salvo que
        // vivan además en otra zona ya abierta. (Es de la región 2 y pide 15
        // medallas: la zona más tardía con especies propias.)
        let central = try unwrap(catalog["senda-helada"])
        let cerrado = access(14, kanto: true)
        let exclusivos = central.species.filter { id in
            catalog.zones(for: id).allSatisfy { !cerrado.opens($0) }
        }
        expectGreaterThan(exclusivos.count, 0, "la zona debe aportar algo propio")

        for rarity in Rarity.allCases {
            let ofrecidas = Set(spawner.candidates(rarity: rarity, access: cerrado).map(\.id))
            for id in exclusivos where !catalog.unassigned.contains(id) {
                expectFalse(ofrecidas.contains(id), "#\(id) sale con la Senda Helada cerrada")
            }
        }
    }

    /// La forma general de lo anterior: no una zona concreta, sino **todas**
    /// con **cualquier** progreso. Es el invariante que se le pide al bombo.
    static func testNothingLeaksFromClosedZones() {
        for medals in 0...16 {
            for kanto in [false, true] {
                let estado = access(medals, kanto: kanto)
                // Solo los tiers que se sortean. El de legendarios sí devuelve
                // los suyos con las zonas cerradas —viven en zonas de campeón,
                // así que el bombo sale vacío y salta la red de "ningún tier
                // sin candidatas"—, pero `availableTiers` no lo ofrece nunca,
                // que es lo que se comprueba justo debajo.
                for rarity in Rarity.allCases where rarity.spawnsInTheWild {
                    for species in spawner.candidates(rarity: rarity, access: estado) {
                        // La red de seguridad de las que no tienen zona es
                        // aparte: no vienen de ninguna ruta.
                        guard !catalog.unassigned.contains(species.id) else { continue }
                        expectTrue(
                            catalog.zones(for: species.id).contains { estado.opens($0) },
                            "#\(species.id) \(species.name) se ofrece con \(medals) medallas y todas sus zonas cerradas"
                        )
                    }
                }
            }
        }
    }

    /// El cortafuegos del que depende lo de arriba: por muchas medallas que
    /// tengas, el tier de legendarios no entra en el sorteo.
    static func testLegendaryTierIsNeverRolled() {
        for rank in TrainerRank.allCases {
            expectFalse(
                spawner.availableTiers(rank: rank).contains(.legendary),
                "\(rank.label) puede sortear el tier de legendarios"
            )
        }
    }

    /// Y por el camino que recorre la app: sorteando rivales de verdad, con
    /// tier incluido, no solo mirando el bombo.
    static func testSpawnStaysInsideOpenZones() {
        var rng = SeededRandomProvider(seed: 4)
        for medals in [0, 2, 4] {
            let estado = access(medals, kanto: false)
            let rank = TrainerRank.rank(forMedals: medals)
            for _ in 0..<5_000 {
                let encounter = spawner.spawn(rank: rank, access: estado, using: &rng)
                guard !catalog.unassigned.contains(encounter.speciesID) else { continue }
                expectTrue(
                    catalog.zones(for: encounter.speciesID).contains { estado.opens($0) },
                    "#\(encounter.speciesID) aparece con \(medals) medallas y sin zona abierta"
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

    static func testFallbackTier() throws {
        // Mew es legendario, así que se ofrece como legendario y no como raro.
        let mew = dex.require(151)
        expectEqual(spawner.fallbackTier(for: mew), Rarity.legendary)
        // Un común o poco común sin zona subiría a raro.
        expectEqual(spawner.fallbackTier(for: dex.require(19)), Rarity.rare, "Rattata (común)")
        expectEqual(spawner.fallbackTier(for: dex.require(92)), Rarity.rare, "Gastly (poco común)")
        expectEqual(spawner.fallbackTier(for: dex.require(147)), Rarity.rare, "Dratini (raro)")

        let legendarias = Set(spawner.candidates(rarity: .legendary, access: access(0)).map(\.id))
        expectTrue(legendarias.contains(151), "Mew entra en el tier legendario")
        let raras = Set(spawner.candidates(rarity: .rare, access: access(0)).map(\.id))
        expectFalse(raras.contains(151), "pero no en el de raros")
    }

    static func testNoTierEverStarves() {
        for medals in [0, 1, 4, 8, 16] {
            for kanto in [false, true] {
                let estado = access(medals, kanto: kanto)
                for rarity in Rarity.allCases {
                    let pool = spawner.candidates(rarity: rarity, access: estado)
                    expectFalse(
                        pool.isEmpty,
                        "\(rarity) sin candidatas con \(medals) medallas y kanto=\(kanto)"
                    )
                    expectTrue(pool.allSatisfy(\.isBaseForm), "\(rarity) ofrece evoluciones")
                }
            }
        }
    }
}
