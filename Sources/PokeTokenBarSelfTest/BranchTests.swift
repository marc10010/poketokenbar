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
        ("Onix no puede ser Steelix hasta abrir Johto", testCrossRegionEvolutionWaitsForTheRegion),
        ("una línea de la región que juegas sí evoluciona", testSameRegionLinesAreNeverBlocked),
        ("Eevee espera por las ramas de la región 2", testEeveeWaitsForTheBranchesOfTheSecondRegion),
        ("once evoluciones cruzan a la región cerrada", testExactlyElevenEdgesCross),
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
        // Espeon y Umbreon son de Johto: sin la región 2 abierta, esas dos
        // ramas esperarían y este test va de las condiciones, no de la puerta.
        store.debugGrandfatherRegion("johto")
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

    /// **Onix → Steelix**: Steelix es de Gen 2, o sea de Johto, que es la
    /// región 2. Un Onix con tokens de sobra se queda Onix hasta que salga el
    /// barco, que es el caso que se pedía y el que el orden de juego hace
    /// posible.
    static func testCrossRegionEvolutionWaitsForTheRegion() throws {
        let store = try primed(species: 95, rival: 19, hour: 12)    // Onix
        store.ingest(UsageEvent(id: "crece", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 95, "sigue siendo Onix")
        expectEqual(store.blockedRegion(for: try unwrap(store.state.activeCompanion)), "Johto")

        store.debugOpenRegion("johto")
        expectEqual(store.blockedRegion(for: try unwrap(store.state.activeCompanion)), nil)
        store.ingest(UsageEvent(id: "ahora-si", inputTokens: 10, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 208, "con Johto abierta, Steelix")
    }

    /// La regla solo bloquea cuando **cruza** de región: una línea de la región
    /// que estás jugando evoluciona sin pedir permiso.
    static func testSameRegionLinesAreNeverBlocked() throws {
        let store = try primed(species: 19, rival: 19, hour: 12)    // Rattata
        expectTrue(!store.openRegions.contains("johto"), "y sin Johto abierta")
        store.ingest(UsageEvent(id: "crece", inputTokens: 260_000, outputTokens: 0, timestamp: at(12)))
        expectEqual(activeForm(store), 20, "Raticate, que es de su misma región")
    }

    /// Eevee es de Kanto y sus cinco ramas se reparten entre las dos regiones:
    /// Vaporeon, Jolteon y Flareon son de Kanto, y Espeon y Umbreon de Johto.
    /// Antes del barco, de noche —cuando la condición pide Umbreon— **espera**
    /// en vez de caer a otra rama, que sería dar la que no se pidió.
    static func testEeveeWaitsForTheBranchesOfTheSecondRegion() throws {
        let deNoche = try primed(species: 133, rival: 19, hour: 23)
        deNoche.ingest(UsageEvent(id: "noche", inputTokens: 260_000, outputTokens: 0, timestamp: at(23)))
        expectEqual(activeForm(deNoche), 133, "Umbreon es de Johto: espera")
        expectEqual(
            deNoche.blockedRegion(for: try unwrap(deNoche.state.activeCompanion)),
            "Johto",
            "y la ficha puede decir por qué"
        )

        // Con un rival de agua sí, porque Vaporeon es de Kanto.
        deNoche.debugSetEncounter(WildEncounter(speciesID: 129, isShiny: false, rarity: .common, maxHP: 10))
        deNoche.ingest(UsageEvent(id: "agua", inputTokens: 20, outputTokens: 0, timestamp: at(23)))
        expectEqual(activeForm(deNoche), 134, "Vaporeon, que no cruza de región")
    }

    /// Cuántos casos toca la regla, contados sobre los datos: si un cambio de
    /// zonas o de orden de regiones los mueve, este test lo dice.
    static func testExactlyElevenEdgesCross() {
        expectEqual(GymCatalog.shared.regions, ["kanto", "johto"], "el orden de juego")

        let crossing = dex.all.flatMap { species in
            species.evolvesInto.compactMap { id -> (Pokemon, Pokemon)? in
                guard let target = dex[id], target.homeRegion != species.homeRegion else { return nil }
                return (species, target)
            }
        }
        expectEqual(crossing.count, 19, "evoluciones que cruzan de región")
        let intoSecond = crossing.filter { $0.1.homeRegion == "Johto" }
        expectEqual(intoSecond.count, 11, "las que esperan al barco")
        expectEqual(
            Set(intoSecond.map { $0.1.name }),
            [
                "Steelix", "Crobat", "Blissey", "Scizor", "Kingdra", "Politoed",
                "Bellossom", "Slowking", "Porygon2", "Espeon", "Umbreon",
            ],
            "las evoluciones que en el canon no existían hasta Gen 2"
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
        store.debugGrandfatherRegion("johto")   // Espeon y Umbreon viven allí

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
