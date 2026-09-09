import Foundation
import PokeTokenBarCore

@MainActor
enum EvolutionServiceTests: TestSuite {
    static let suiteName = "EvolutionService"

    static let tests: [(String, () throws -> Void)] = [
        ("stage thresholds match the spec", testStageThresholdsMatchTheSpec),
        ("la forma sale de lo que ha evolucionado, no de sus tokens", testFormFollowsRecordedEvolutions),
        ("two stage lines stop at their last form", testTwoStageLinesStopAtTheirLastForm),
        ("single form lines never evolve", testSingleFormLinesNeverEvolve),
        ("una captura ya evolucionada no retrocede", testACapturedEvolvedFormNeverDevolves),
        ("ninguna de las 251 retrocede al capturarla", testNoSpeciesDevolvesOnCapture),
        ("el camino pasa por la especie capturada", testChainPathGoesThroughTheCapturedSpecies),
        ("la rama sale del tipo de lo que vence", testBranchComesFromWhatItDefeated),
        ("y si no, de la banda del reloj", testBranchFallsBackToTheClock),
        ("el tipo manda sobre el reloj", testDefeatedTypeBeatsTheClock),
        ("Politoed es la rama por defecto de Poliwhirl", testPoliwhirlFallsBackToPolitoed),
        ("todas las ramas de las cinco líneas son alcanzables", testEveryBranchIsReachable),
        ("next form previews the upcoming stage", testNextFormPreviewsTheUpcomingStage),
    ]

    private static let service = EvolutionService()
    private static let dex = Pokedex.shared

    /// Calendario fijo: la rama depende de la hora, así que un test no puede
    /// depender de a qué hora se ejecute.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func at(_ hour: Int) -> Date {
        utc.date(from: DateComponents(timeZone: utc.timeZone, year: 2026, month: 9, day: 9, hour: hour)) ?? Date()
    }

    private static func branch(_ captured: CapturedPokemon, defeating types: [String], hour: Int) -> Int? {
        service.branch(for: captured, defeatedTypes: types, at: at(hour), calendar: utc)?.id
    }

    private static func captured(_ speciesID: Int, seed: UInt64 = 1, earned: Int = 0) -> CapturedPokemon {
        CapturedPokemon(
            speciesID: speciesID,
            isShiny: false,
            capturedAtTotalTokens: 0,
            evolutionSeed: seed,
            tokensEarned: earned
        )
    }

    static func testStageThresholdsMatchTheSpec() {
        expectEqual(EvolutionStage.stage(forTotalTokens: 0), .base)
        expectEqual(EvolutionStage.stage(forTotalTokens: 200_000), .base)
        expectEqual(EvolutionStage.stage(forTotalTokens: 200_001), .one)
        expectEqual(EvolutionStage.stage(forTotalTokens: 1_000_000), .one)
        expectEqual(EvolutionStage.stage(forTotalTokens: 1_000_001), .two)
    }

    /// Los tokens dan **derecho** a evolucionar; la evolución la hace el
    /// combate y queda escrita. Antes la forma se derivaba de los tokens, y por
    /// eso la rama estaba echada desde la captura.
    static func testFormFollowsRecordedEvolutions() {
        let bulbasaur = captured(1)
        expectEqual(service.currentForm(of: bulbasaur.earning(5_000_000)).id, 1, "con tokens de sobra sigue siendo Bulbasaur")
        expectTrue(service.canEvolve(bulbasaur.earning(5_000_000)), "pero tiene derecho")
        expectTrue(!service.canEvolve(bulbasaur.earning(100)), "y con pocos, no")

        let ivysaur = bulbasaur.earning(500_000).evolved(to: 2)
        expectEqual(service.currentForm(of: ivysaur).id, 2)
        expectEqual(service.stage(of: ivysaur), .one)
        expectTrue(!service.canEvolve(ivysaur), "500k no llegan a la etapa 2")

        let venusaur = bulbasaur.earning(5_000_000).evolved(to: 2, 3)
        expectEqual(service.currentForm(of: venusaur).id, 3)
        expectEqual(service.stage(of: venusaur), .two)
        expectTrue(!service.canEvolve(venusaur), "su línea acaba aquí")
    }

    static func testTwoStageLinesStopAtTheirLastForm() {
        // Sentret -> Furret y ahí acaba: la etapa 2 no inventa una forma.
        let furret = captured(161).earning(5_000_000).evolved(to: 162)
        expectEqual(service.currentForm(of: furret).id, 162)
        expectNil(service.nextForm(of: furret))
        expectTrue(!service.canEvolve(furret))
        expectTrue(service.options(for: furret).isEmpty)
    }

    static func testSingleFormLinesNeverEvolve() {
        let lapras = captured(131).earning(9_000_000)
        expectEqual(service.currentForm(of: lapras).id, 131)
        expectTrue(!service.canEvolve(lapras))
    }

    /// Antes esto era lo contrario: capturar un Venusaur con poco histórico
    /// mostraba **Bulbasaur**, porque la forma se resolvía siempre desde la
    /// base. Retroceder no es una etapa: la etapa que ya trae al capturarlo es
    /// su suelo.
    static func testACapturedEvolvedFormNeverDevolves() {
        let venusaur = captured(3, earned: 0)
        expectEqual(service.currentForm(of: venusaur).id, 3)
        expectEqual(service.stage(of: venusaur), .two)
        expectNil(service.nextForm(of: venusaur), "su línea acaba en él")

        // Pikachu está en medio de Pichu -> Pikachu -> Raichu: se queda
        // Pikachu y le sigue faltando llegar a la etapa 2 para ser Raichu.
        let pikachu = captured(25, earned: 0)
        expectEqual(service.currentForm(of: pikachu).id, 25)
        expectEqual(service.stage(of: pikachu), .one)
        expectEqual(service.nextForm(of: pikachu)?.id, 26)
        expectTrue(!service.canEvolve(pikachu.earning(500_000)), "500k no llegan a la etapa 2")
        expectTrue(service.canEvolve(pikachu.earning(1_000_001)))
        expectEqual(service.currentForm(of: pikachu.earning(1_000_001).evolved(to: 26)).id, 26)
    }

    /// La forma que se ve al capturar es la que se capturó, para las 251. Es la
    /// invariante que impide que vuelva a colarse una devolución por una rama
    /// que la semilla no habría elegido.
    static func testNoSpeciesDevolvesOnCapture() {
        for species in Pokedex.shared.all {
            let fresh = captured(species.id, seed: UInt64(species.id) * 7 + 1)
            expectEqual(
                service.currentForm(of: fresh).id,
                species.id,
                "#\(species.id) \(species.name) se dibuja como otra al capturarlo"
            )
        }
    }

    static func testChainPathGoesThroughTheCapturedSpecies() {
        // Vaporeon es una rama de Eevee entre cinco: la semilla habría elegido
        // otra, y aun así el camino tiene que pasar por él.
        for seed in [1, 2, 3, 99, 8_675_309] as [UInt64] {
            let vaporeon = captured(134, seed: seed)
            let path = service.chainPath(of: vaporeon).map(\.id)
            expectTrue(path.contains(134), "semilla \(seed): \(path)")
            expectEqual(path.first, 133, "y arranca en Eevee")
            expectEqual(service.currentForm(of: vaporeon).id, 134)
        }
    }

    /// La traducción de las piedras evolutivas: no hay objetos, pero sí
    /// rivales con tipo. Vencer un tipo agua con un Eevee da Vaporeon.
    static func testBranchComesFromWhatItDefeated() {
        let eevee = captured(133).earning(300_000)
        expectEqual(branch(eevee, defeating: ["water"], hour: 3), 134, "Vaporeon")
        expectEqual(branch(eevee, defeating: ["electric"], hour: 3), 135, "Jolteon")
        expectEqual(branch(eevee, defeating: ["fire"], hour: 3), 136, "Flareon")

        let poliwhirl = captured(60).earning(2_000_000).evolved(to: 61)
        expectEqual(branch(poliwhirl, defeating: ["water", "flying"], hour: 12), 62, "Poliwrath")
    }

    /// Espeon y Umbreon se quedan con su canon —día y noche— y Tyrogue, cuyo
    /// canon mira estadísticas que aquí no varían, con tres tramos de reloj.
    static func testBranchFallsBackToTheClock() {
        let eevee = captured(133).earning(300_000)
        expectEqual(branch(eevee, defeating: ["normal"], hour: 12), 196, "Espeon de día")
        expectEqual(branch(eevee, defeating: ["normal"], hour: 23), 197, "Umbreon de noche")
        expectEqual(branch(eevee, defeating: [], hour: 6), 196, "a las 6 ya es de día")
        expectEqual(branch(eevee, defeating: [], hour: 5), 197, "a las 5 todavía no")

        let gloom = captured(43).earning(2_000_000).evolved(to: 44)
        expectEqual(branch(gloom, defeating: ["normal"], hour: 12), 182, "Bellossom de día")
        expectEqual(branch(gloom, defeating: ["normal"], hour: 22), 45, "Vileplume de noche")

        let slowpoke = captured(79).earning(300_000)
        expectEqual(branch(slowpoke, defeating: ["normal"], hour: 12), 80, "Slowbro de día")
        expectEqual(branch(slowpoke, defeating: ["normal"], hour: 22), 199, "Slowking de noche")

        let tyrogue = captured(236).earning(300_000)
        expectEqual(branch(tyrogue, defeating: [], hour: 9), 106, "Hitmonlee por la mañana")
        expectEqual(branch(tyrogue, defeating: [], hour: 17), 107, "Hitmonchan por la tarde")
        expectEqual(branch(tyrogue, defeating: [], hour: 23), 237, "Hitmontop de noche")
    }

    /// El reloj es el camino por defecto y el tipo el que se busca a
    /// propósito, así que el tipo gana: si no, de noche no habría manera de
    /// sacar a Vaporeon.
    static func testDefeatedTypeBeatsTheClock() {
        let eevee = captured(133).earning(300_000)
        expectEqual(branch(eevee, defeating: ["water"], hour: 23), 134, "de noche pero vence a un agua")
        expectEqual(branch(eevee, defeating: ["fire"], hour: 12), 136, "de día pero vence a un fuego")
    }

    static func testPoliwhirlFallsBackToPolitoed() {
        // Politoed pedía Roca del Rey e intercambio, que no existen: es la
        // rama que sale cuando no se cumple la del agua.
        let poliwhirl = captured(60).earning(2_000_000).evolved(to: 61)
        expectEqual(branch(poliwhirl, defeating: ["grass"], hour: 12), 186)
        expectEqual(branch(poliwhirl, defeating: [], hour: 23), 186)
    }

    /// La invariante que justifica la mecánica: con estas condiciones **las 15
    /// ramas de las cinco líneas se pueden conseguir**. Si una no fuera
    /// alcanzable, quedaría un hueco muerto en la Pokédex.
    static func testEveryBranchIsReachable() throws {
        let types = ["water", "electric", "fire", "normal", "grass", "psychic"]
        for (formID, options) in BranchRules.table {
            let holder = try unwrap(dex[formID])
            let owner = captured(holder.baseFormID)
                .earning(5_000_000)
                .evolvedTo(pathTo(formID, from: holder.baseFormID))
            var reached: Set<Int> = []
            for hour in 0..<24 {
                for type in types + [""] {
                    if let id = branch(owner, defeating: type.isEmpty ? [] : [type], hour: hour) {
                        reached.insert(id)
                    }
                }
            }
            expectEqual(reached, Set(options.map(\.form)), "las ramas de #\(formID)")
        }
    }

    /// Pasos desde la forma base hasta `formID`, para montar el fixture.
    private static func pathTo(_ formID: Int, from baseID: Int) -> [Int] {
        guard formID != baseID else { return [] }
        var path: [Int] = [formID]
        var current = formID
        while let parent = dex.parent(of: current), parent.id != baseID {
            path.insert(parent.id, at: 0)
            current = parent.id
        }
        return path
    }

    static func testNextFormPreviewsTheUpcomingStage() {
        expectEqual(service.nextForm(of: captured(1, earned: 0))?.id, 2)
        expectEqual(service.nextForm(of: captured(1, earned: 300_000).evolved(to: 2))?.id, 3)
        expectNil(service.nextForm(of: captured(1, earned: 2_000_000).evolved(to: 2, 3)))
        // Una línea que bifurca no tiene "siguiente forma" que anunciar: la
        // decide lo que venzas, y eso lo dice `branch(for:)`.
        expectNil(service.nextForm(of: captured(133, earned: 300_000)))
    }
}
