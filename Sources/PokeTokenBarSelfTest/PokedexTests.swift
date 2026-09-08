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
        ("las cadenas con raíz fuera del dex enlazan", testChainsRootedOutsideTheDexStillLink),
        ("los enlaces evolutivos son consistentes", testEvolutionLinksAreConsistent),
        ("nada con precursor figura como base", testNothingWithAPreEvolutionIsABaseForm),
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

    /// El bug que esto fija: las cadenas cuya raíz es una cría de una
    /// generación posterior (Azurill, Happiny) se descartaban enteras, así que
    /// Marill no podía evolucionar a Azumarill ni Chansey a Blissey.
    static func testChainsRootedOutsideTheDexStillLink() {
        expectEqual(dex.require(183).evolvesInto, [184], "Marill → Azumarill")
        expectEqual(dex.require(184).stage, 1)
        expectEqual(dex.require(184).baseFormID, 183)
        expectEqual(dex.require(113).evolvesInto, [242], "Chansey → Blissey")
        expectEqual(dex.require(242).stage, 1)
        expectEqual(dex.require(242).baseFormID, 113)
        // Snorlax sí es base aunque su cadena arranque en Munchlax, fuera de
        // rango: el primero dentro de rango es él.
        expectEqual(dex.require(143).stage, 0)
        expectEqual(dex.require(143).baseFormID, 143)
    }

    /// Invariante general: una evolución está en la misma línea que su origen y
    /// una etapa por encima. Es lo que se rompía sin que nadie lo notara.
    static func testEvolutionLinksAreConsistent() {
        for species in dex.all {
            for nextID in species.evolvesInto {
                let next = dex.require(nextID)
                expectEqual(
                    next.baseFormID,
                    species.baseFormID,
                    "\(next.name) debería estar en la línea de \(species.name)"
                )
                expectEqual(next.stage, species.stage + 1, "\(next.name) tras \(species.name)")
            }
        }
    }

    /// Y nadie con precursor dentro de la Pokédex puede figurar como base: eso
    /// lo convertiría en una línea aparte y se podría capturar por duplicado.
    static func testNothingWithAPreEvolutionIsABaseForm() {
        let evolved = Set(dex.all.flatMap(\.evolvesInto))
        for id in evolved {
            let species = dex.require(id)
            expectGreaterThan(species.stage, 0, "\(species.name) tiene precursor y sale como base")
            expectFalse(species.isBaseForm, species.name)
        }
    }

    static func testSpawnCandidatesAreBaseFormsOnly() {
        for rarity in Rarity.allCases {
            let pool = dex.spawnCandidates(rarity: rarity)
            expectFalse(pool.isEmpty, "\(rarity) sin candidatos")
            expectTrue(pool.allSatisfy(\.isBaseForm), "\(rarity) incluye evoluciones")
        }
    }
}
