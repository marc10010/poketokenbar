import Foundation
import PokeTokenBarCore

@MainActor
enum PokedexTests: TestSuite {
    static let suiteName = "Pokedex"

    static let tests: [(String, () throws -> Void)] = [
        ("covers generations one and two only", testCoversGenerationsOneAndTwoOnly),
        ("rarity matches spec examples", testRarityMatchesSpecExamples),
        ("starters are rare base forms", testStartersAreRareBaseForms),
        ("evolution chains are linked", testEvolutionChainsAreLinked),
        ("spawn candidates are base forms only", testSpawnCandidatesAreBaseFormsOnly),
    ]

    private static let dex = Pokedex.shared

    static func testCoversGenerationsOneAndTwoOnly() {
        expectEqual(dex.all.count, 251)
        expectEqual(dex.all.first?.id, 1)
        expectEqual(dex.all.last?.id, 251)
        expectTrue(dex.all.allSatisfy { (1...251).contains($0.id) })
    }

    static func testRarityMatchesSpecExamples() {
        expectEqual(dex.require(19).rarity, .common, "Rattata")
        expectEqual(dex.require(161).rarity, .common, "Sentret")
        expectEqual(dex.require(92).rarity, .uncommon, "Gastly")
        expectEqual(dex.require(123).rarity, .uncommon, "Scyther")
        expectEqual(dex.require(147).rarity, .rare, "Dratini")
        expectEqual(dex.require(246).rarity, .rare, "Larvitar")
        expectEqual(dex.require(150).rarity, .legendary, "Mewtwo")
        expectEqual(dex.require(249).rarity, .legendary, "Lugia")
    }

    static func testStartersAreRareBaseForms() {
        expectEqual(dex.starters.map(\.id), [1, 4, 7, 152, 155, 158])
        expectTrue(dex.starters.allSatisfy { $0.rarity == .rare && $0.isBaseForm })
    }

    static func testEvolutionChainsAreLinked() {
        expectEqual(dex.require(1).evolvesInto, [2])
        expectEqual(dex.require(2).evolvesInto, [3])
        expectTrue(dex.require(3).evolvesInto.isEmpty)
        expectEqual(dex.require(133).evolvesInto.count, 5, "Eevee bifurca")
        expectEqual(dex.require(3).baseFormID, 1)
        expectEqual(dex.require(3).stage, 2)
    }

    static func testSpawnCandidatesAreBaseFormsOnly() {
        for rarity in Rarity.allCases {
            let pool = dex.spawnCandidates(rarity: rarity)
            expectFalse(pool.isEmpty, "\(rarity) sin candidatos")
            expectTrue(pool.allSatisfy(\.isBaseForm), "\(rarity) incluye evoluciones")
        }
    }
}
