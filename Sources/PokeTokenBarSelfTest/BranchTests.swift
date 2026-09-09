import Foundation
import PokeTokenBarCore

@MainActor
enum BranchTests: TestSuite {
    static let suiteName = "Ramas"

    static let tests: [(String, () throws -> Void)] = [
        ("evoluciona con el tipo de lo que acaba de vencer", testEvolvesByTheDefeatedType),
        ("el reloj decide cuando el tipo no dice nada", testClockDecidesWhenTypeDoesNot),
        ("el segundo Eevee solo sale con el primero ya evolucionado", testSecondSpecimenNeedsTheFirstEvolved),
        ("una línea recta nunca acepta un segundo ejemplar", testLinearLinesStillRejectDuplicates),
        ("la migración conserva la forma que ya se veía", testMigrationKeepsTheVisibleForm),
        ("las cinco ramas de Eevee acaban registradas", testAllFiveEeveeBranchesEndUpRegistered),
        ("un bebé de Johto no crece hasta abrir Kanto", testCrossRegionEvolutionWaitsForTheRegion),
        ("una línea de Kanto sí evoluciona en Johto", testSameRegionLinesAreNeverBlocked),
        ("Tyrogue toma la rama que su región permite", testTyrogueTakesTheReachableBranch),
        ("solo ocho evoluciones cruzan a una región cerrada", testExactlyEightEdgesCross),
    ]

    private static let dex = Pokedex.shared

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func at(_ hour: Int) -> Date {
        utc.date(from: DateComponents(timeZone: utc.timeZone, year: 2026, month: 9, day: 9, hour: hour)) ?? Date()
    }

    private static func makeStore(seed: UInt64 = 31) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed),
            calendar: utc
        )
    }

    /// Deja al jugador con un Eevee equipado y sin efectividad de tipos, para
    /// que el daño sea 1 a 1 y los números del test se lean.
    private static func withEevee(hour: Int, rival: Int, rivalHP: Int = 250_000) throws -> GameStore {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        store.debugCapture(speciesID: 133)
        let eevee = try unwrap(store.state.box.last)
        store.setActiveCompanion(eevee.id)
        store.debugSetEncounter(WildEncounter(speciesID: rival, isShiny: false, rarity: .common, maxHP: rivalHP))
        return store
    }

    private static func activeForm(_ store: GameStore) -> Int? { store.activeForm?.id }

    /// Deja un ejemplar equipado con tokens de sobra y un rival del tipo dado.
    private static func primed(species: Int, rival: Int, hour: Int) throws -> GameStore {
        let store = makeStore()
        store.chooseStarter(speciesID: 152)      // Chikorita, de Johto
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        store.debugCapture(speciesID: species)
        let mine = try unwrap(store.state.box.last)
        store.setActiveCompanion(mine.id)
        store.debugSetEncounter(WildEncounter(speciesID: rival, isShiny: false, rarity: .common, maxHP: 250_000))
        return store
    }

    /// Pikachu vive en Kanto, así que un Pichu de Johto se queda Pichu hasta
    /// que salga el barco. Es la regla que se pidió, con el ejemplo invertido
    /// respecto a Onix → Steelix: Steelix es de Johto y por tanto nunca espera.
    static func testCrossRegionEvolutionWaitsForTheRegion() throws {
        let store = try primed(species: 172, rival: 19, hour: 12)   // Pichu
        store.ingest(UsageEvent(id: "crece", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 172, "sigue siendo Pichu")
        expectEqual(store.blockedRegion(for: try unwrap(store.state.activeCompanion)), "Kanto")

        store.debugOpenRegion("kanto")
        expectEqual(store.blockedRegion(for: try unwrap(store.state.activeCompanion)), nil)
        store.ingest(UsageEvent(id: "ahora-si", inputTokens: 10, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 25, "con Kanto abierta, Pikachu")
    }

    /// La regla solo bloquea cuando **cruza** de región. Las rutas de Johto
    /// están llenas de especies de Kanto y congelarlas sería un muro, no una
    /// regla: 50 de las líneas capturables antes del barco son de Kanto.
    static func testSameRegionLinesAreNeverBlocked() throws {
        let store = try primed(species: 19, rival: 19, hour: 12)    // Rattata
        expectTrue(!store.zoneAccess.kantoOpen, "y sin Kanto abierta")
        store.ingest(UsageEvent(id: "crece", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 20, "Raticate, que es de su misma región")
    }

    /// Hitmontop es de Johto y los otros dos de Kanto, así que antes del barco
    /// solo la rama de la noche está disponible — y no se cae a otra: por la
    /// mañana espera.
    static func testTyrogueTakesTheReachableBranch() throws {
        let deNoche = try primed(species: 236, rival: 19, hour: 23)
        deNoche.ingest(UsageEvent(id: "noche", inputTokens: 260_000, outputTokens: 0, timestamp: at(23)))
        expectEqual(activeForm(deNoche), 237, "Hitmontop, de Johto")

        let porLaManana = try primed(species: 236, rival: 19, hour: 9)
        porLaManana.ingest(UsageEvent(id: "manana", inputTokens: 260_000, outputTokens: 0, timestamp: at(9)))
        expectEqual(activeForm(porLaManana), 236, "Hitmonlee es de Kanto: espera")
        expectEqual(
            porLaManana.blockedRegion(for: try unwrap(porLaManana.state.activeCompanion)),
            "Kanto",
            "y la ficha puede decir por qué"
        )
    }

    /// Cuántos casos toca la regla, contados sobre los datos: si un cambio de
    /// zonas o de orden de regiones los mueve, este test lo dice.
    static func testExactlyEightEdgesCross() {
        let johtoFirst = GymCatalog.shared.regions.first == "johto"
        expectTrue(johtoFirst, "el orden de regiones es Johto y luego Kanto")

        let crossing = dex.all.flatMap { species in
            species.evolvesInto.compactMap { id -> (Pokemon, Pokemon)? in
                guard let target = dex[id], target.homeRegion != species.homeRegion else { return nil }
                return (species, target)
            }
        }
        expectEqual(crossing.count, 19, "evoluciones que cruzan de región")
        let intoKanto = crossing.filter { $0.1.homeRegion == "Kanto" }
        expectEqual(intoKanto.count, 8, "las que esperan al barco")
        expectEqual(
            Set(intoKanto.map { $0.0.name }),
            ["Pichu", "Cleffa", "Igglybuff", "Tyrogue", "Smoochum", "Elekid", "Magby"],
            "los bebés de Johto"
        )
    }

    /// El evento tumba al rival y deja al Eevee pasado de los 200k, así que la
    /// rama la decide ese rival: Magikarp es agua, o sea Vaporeon.
    static func testEvolvesByTheDefeatedType() throws {
        let conAgua = try withEevee(hour: 23, rival: 129)      // Magikarp, agua
        conAgua.ingest(UsageEvent(id: "agua", inputTokens: 260_000, outputTokens: 0, timestamp: at(23)))
        expectEqual(activeForm(conAgua), 134, "Vaporeon, y de noche: el tipo manda")

        let conFuego = try withEevee(hour: 12, rival: 58)      // Growlithe, fuego
        conFuego.ingest(UsageEvent(id: "fuego", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(conFuego), 136, "Flareon, y de día")

        let conElectrico = try withEevee(hour: 12, rival: 81)  // Magnemite, eléctrico
        conElectrico.ingest(UsageEvent(id: "elec", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(conElectrico), 135, "Jolteon")
    }

    static func testClockDecidesWhenTypeDoesNot() throws {
        let deDia = try withEevee(hour: 12, rival: 19)         // Rattata, normal
        deDia.ingest(UsageEvent(id: "dia", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(deDia), 196, "Espeon")

        let deNoche = try withEevee(hour: 23, rival: 19)
        deNoche.ingest(UsageEvent(id: "noche", inputTokens: 260_000, outputTokens: 0, timestamp: at(23)))
        expectEqual(activeForm(deNoche), 197, "Umbreon")
    }

    /// La secuencia que se pidió: evolucionas el que tienes y **entonces**
    /// puede salir otro, en vez de acumular cinco Eevees sin evolucionar.
    static func testSecondSpecimenNeedsTheFirstEvolved() throws {
        let store = try withEevee(hour: 12, rival: 19)
        expectTrue(!store.acceptsAnother(baseFormID: 133, shiny: false), "con un Eevee sin evolucionar, no")

        store.ingest(UsageEvent(id: "evoluciona", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 196, "ya es Espeon")
        expectTrue(store.acceptsAnother(baseFormID: 133, shiny: false), "y ahora sí puede salir otro")

        // Con las cinco ramas registradas ya no hace falta ningún Eevee más.
        for id in [134, 135, 136, 197] { store.debugRegister(speciesID: id) }
        expectTrue(!store.acceptsAnother(baseFormID: 133, shiny: false), "no faltan ramas")
    }

    static func testLinearLinesStillRejectDuplicates() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        expectTrue(!store.acceptsAnother(baseFormID: 7, shiny: false), "Squirtle no bifurca")
        store.debugCapture(speciesID: 19)
        expectTrue(!store.acceptsAnother(baseFormID: 19, shiny: false), "ni Rattata")
    }

    /// Una partida de la versión anterior no puede cambiar de forma al abrir la
    /// app: lo que se veía se escribe como historia.
    static func testMigrationKeepsTheVisibleForm() throws {
        let url = TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
        let legacy: [String: Any] = [
            "schemaVersion": 6,
            "box": [
                [
                    "id": UUID().uuidString,
                    "speciesID": 104,
                    "isShiny": false,
                    "capturedAt": "2026-09-01T10:00:00Z",
                    "capturedAtTotalTokens": 0,
                    "evolutionSeed": 7,
                    "tokensEarned": 300_000,
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)

        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 1), calendar: utc)
        let cubone = try unwrap(store.state.box.first)
        expectEqual(cubone.evolvedForms, [105], "el Marowak que ya se veía queda escrito")
        expectEqual(store.form(of: cubone).id, 105)
        expectEqual(store.state.schemaVersion, GameState.currentSchemaVersion)
    }

    /// El objetivo de toda la mecánica: las cinco ramas de Eevee se pueden
    /// registrar, una por ejemplar, y el registro no las pierde.
    static func testAllFiveEeveeBranchesEndUpRegistered() throws {
        let store = makeStore()
        store.chooseStarter(speciesID: 7)
        store.updateSettings { $0.typeEffectivenessEnabled = false }

        let plan: [(rival: Int, hour: Int, expected: Int)] = [
            (129, 23, 134),   // Magikarp, agua -> Vaporeon
            (81, 12, 135),    // Magnemite, eléctrico -> Jolteon
            (58, 12, 136),    // Growlithe, fuego -> Flareon
            (19, 12, 196),    // Rattata de día -> Espeon
            (19, 23, 197),    // Rattata de noche -> Umbreon
        ]

        for (index, step) in plan.enumerated() {
            // Contadores a cero en cada paso: con un gimnasio abierto los
            // tokens irían contra el líder, no habría salvaje vencido y la
            // rama saldría con el rival de la vuelta anterior.
            store.debugSetGymCounters(tokens: 0, captures: 0)
            expectTrue(
                index == 0 || store.acceptsAnother(baseFormID: 133, shiny: false),
                "el paso \(index) necesita poder capturar otro Eevee"
            )
            store.debugCapture(speciesID: 133)
            let eevee = try unwrap(store.state.box.last)
            store.setActiveCompanion(eevee.id)
            store.debugSetEncounter(WildEncounter(speciesID: step.rival, isShiny: false, rarity: .common, maxHP: 250_000))
            store.ingest(UsageEvent(id: "rama-\(index)", inputTokens: 260_000, outputTokens: 0, timestamp: at(step.hour)))
            expectEqual(store.activeForm?.id, step.expected, "paso \(index)")
        }

        let registered = store.state.registeredSpeciesIDs
        for branch in [134, 135, 136, 196, 197] {
            expectTrue(registered.contains(branch), "falta la rama #\(branch) en el registro")
        }
        expectEqual(
            store.pokedexEntries.filter { [134, 135, 136, 196, 197].contains($0.species.id) && $0.isCaptured }.count,
            5,
            "las cinco cuentan para la Pokédex"
        )
    }
}
