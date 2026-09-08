import Foundation
import PokeTokenBarCore

@MainActor
enum EvolutionServiceTests: TestSuite {
    static let suiteName = "EvolutionService"

    static let tests: [(String, () throws -> Void)] = [
        ("stage thresholds match the spec", testStageThresholdsMatchTheSpec),
        ("form follows the accumulated history", testFormFollowsTheAccumulatedHistory),
        ("two stage lines stop at their last form", testTwoStageLinesStopAtTheirLastForm),
        ("single form lines never evolve", testSingleFormLinesNeverEvolve),
        ("an evolved species resolves from its base form", testAnEvolvedSpeciesResolvesFromItsBaseForm),
        ("branching is stable for the same seed", testBranchingIsStableForTheSameSeed),
        ("different seeds can take different branches", testDifferentSeedsCanTakeDifferentBranches),
        ("next form previews the upcoming stage", testNextFormPreviewsTheUpcomingStage),
    ]

    private static let service = EvolutionService()

    private static func captured(_ speciesID: Int, seed: UInt64 = 1) -> CapturedPokemon {
        CapturedPokemon(speciesID: speciesID, isShiny: false, capturedAtTotalTokens: 0, evolutionSeed: seed)
    }

    static func testStageThresholdsMatchTheSpec() {
        expectEqual(EvolutionStage.stage(forTotalTokens: 0), .base)
        expectEqual(EvolutionStage.stage(forTotalTokens: 200_000), .base)
        expectEqual(EvolutionStage.stage(forTotalTokens: 200_001), .one)
        expectEqual(EvolutionStage.stage(forTotalTokens: 1_000_000), .one)
        expectEqual(EvolutionStage.stage(forTotalTokens: 1_000_001), .two)
    }

    static func testFormFollowsTheAccumulatedHistory() {
        let bulbasaur = captured(1)
        expectEqual(service.currentForm(of: bulbasaur, totalTokens: 0).id, 1)
        expectEqual(service.currentForm(of: bulbasaur, totalTokens: 500_000).id, 2)
        expectEqual(service.currentForm(of: bulbasaur, totalTokens: 5_000_000).id, 3)
    }

    static func testTwoStageLinesStopAtTheirLastForm() {
        // Sentret -> Furret y ahí acaba: la etapa 2 no inventa una forma.
        let sentret = captured(161)
        expectEqual(service.currentForm(of: sentret, totalTokens: 5_000_000).id, 162)
        expectNil(service.nextForm(of: sentret, totalTokens: 5_000_000))
    }

    static func testSingleFormLinesNeverEvolve() {
        let lapras = captured(131)
        expectEqual(service.currentForm(of: lapras, totalTokens: 9_000_000).id, 131)
    }

    static func testAnEvolvedSpeciesResolvesFromItsBaseForm() {
        // Capturar un Venusaur (#3) con poco histórico muestra Bulbasaur.
        expectEqual(service.currentForm(of: captured(3), totalTokens: 0).id, 1)
    }

    static func testBranchingIsStableForTheSameSeed() {
        let eevee = captured(133, seed: 8_675_309)
        let first = service.currentForm(of: eevee, totalTokens: 500_000).id
        for _ in 0..<20 {
            expectEqual(service.currentForm(of: eevee, totalTokens: 500_000).id, first)
        }
        expectTrue([134, 135, 136, 196, 197].contains(first))
    }

    static func testDifferentSeedsCanTakeDifferentBranches() {
        let branches = Set((0..<80).map { seed in
            service.currentForm(of: captured(133, seed: UInt64(seed) * 7919 + 1), totalTokens: 400_000).id
        })
        expectGreaterThan(branches.count, 1, "el seed debería repartir las ramas de Eevee")
    }

    static func testNextFormPreviewsTheUpcomingStage() {
        expectEqual(service.nextForm(of: captured(1), totalTokens: 0)?.id, 2)
        expectEqual(service.nextForm(of: captured(1), totalTokens: 300_000)?.id, 3)
        expectNil(service.nextForm(of: captured(1), totalTokens: 2_000_000))
    }
}
