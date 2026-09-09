import Foundation
import PokeTokenBarCore

@MainActor
enum EvolutionServiceTests: TestSuite {
    static let suiteName = "EvolutionService"

    static let tests: [(String, () throws -> Void)] = [
        ("stage thresholds match the spec", testStageThresholdsMatchTheSpec),
        ("la forma sigue sus propios tokens", testFormFollowsItsOwnEarnedTokens),
        ("two stage lines stop at their last form", testTwoStageLinesStopAtTheirLastForm),
        ("single form lines never evolve", testSingleFormLinesNeverEvolve),
        ("una captura ya evolucionada no retrocede", testACapturedEvolvedFormNeverDevolves),
        ("ninguna de las 251 retrocede al capturarla", testNoSpeciesDevolvesOnCapture),
        ("el camino pasa por la especie capturada", testChainPathGoesThroughTheCapturedSpecies),
        ("branching is stable for the same seed", testBranchingIsStableForTheSameSeed),
        ("different seeds can take different branches", testDifferentSeedsCanTakeDifferentBranches),
        ("next form previews the upcoming stage", testNextFormPreviewsTheUpcomingStage),
    ]

    private static let service = EvolutionService()

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

    static func testFormFollowsItsOwnEarnedTokens() {
        let bulbasaur = captured(1)
        expectEqual(service.currentForm(of: bulbasaur.earning(0)).id, 1)
        expectEqual(service.currentForm(of: bulbasaur.earning(500_000)).id, 2)
        expectEqual(service.currentForm(of: bulbasaur.earning(5_000_000)).id, 3)
    }

    static func testTwoStageLinesStopAtTheirLastForm() {
        // Sentret -> Furret y ahí acaba: la etapa 2 no inventa una forma.
        let sentret = captured(161)
        expectEqual(service.currentForm(of: sentret.earning(5_000_000)).id, 162)
        expectNil(service.nextForm(of: sentret.earning(5_000_000)))
    }

    static func testSingleFormLinesNeverEvolve() {
        let lapras = captured(131)
        expectEqual(service.currentForm(of: lapras.earning(9_000_000)).id, 131)
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
        expectEqual(service.currentForm(of: pikachu.earning(1_000_001)).id, 26)
        // Y por debajo del umbral de la etapa 2 sigue siendo Pikachu, no baja.
        expectEqual(service.currentForm(of: pikachu.earning(500_000)).id, 25)
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

    static func testBranchingIsStableForTheSameSeed() {
        let eevee = captured(133, seed: 8_675_309)
        let first = service.currentForm(of: eevee.earning(500_000)).id
        for _ in 0..<20 {
            expectEqual(service.currentForm(of: eevee.earning(500_000)).id, first)
        }
        expectTrue([134, 135, 136, 196, 197].contains(first))
    }

    static func testDifferentSeedsCanTakeDifferentBranches() {
        let branches = Set((0..<80).map { seed in
            service.currentForm(of: captured(133, seed: UInt64(seed) * 7919 + 1, earned: 400_000)).id
        })
        expectGreaterThan(branches.count, 1, "el seed debería repartir las ramas de Eevee")
    }

    static func testNextFormPreviewsTheUpcomingStage() {
        expectEqual(service.nextForm(of: captured(1, earned: 0))?.id, 2)
        expectEqual(service.nextForm(of: captured(1, earned: 300_000))?.id, 3)
        expectNil(service.nextForm(of: captured(1, earned: 2_000_000)))
    }
}
