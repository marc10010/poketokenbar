import Foundation
import PokeTokenBarCore

@MainActor
enum TypeChartTests: TestSuite {
    static let suiteName = "TypeChart"

    static let tests: [(String, () throws -> Void)] = [
        ("cubre todos los tipos que usa la pokédex", testCoversEveryTypeInTheDex),
        ("las ventajas clásicas salen bien", testClassicMatchups),
        ("los tipos del defensor multiplican", testDualTypeDefendersMultiply),
        ("el atacante usa su mejor tipo", testAttackerPicksItsBestType),
        ("la inmunidad no atasca el combate", testImmunityFallsToTheFloor),
        ("el multiplicador está acotado", testMultiplierIsBounded),
        ("los pokémon reales cuadran con la tabla", testRealPokemonMatchups),
    ]

    private static let chart = TypeChart.shared
    private static let dex = Pokedex.shared

    /// La Pokédex embebida trae los tipos actuales, así que incluye Hada
    /// (Clefairy, Togepi, Marill...). Ningún tipo puede quedarse sin tabla: si
    /// pasara, ese cruce caería a neutro en silencio.
    static func testCoversEveryTypeInTheDex() {
        expectEqual(chart.types.count, 18)
        let used = Set(dex.all.flatMap(\.types))
        expectTrue(used.isSubset(of: Set(chart.types)), "tipos sin tabla: \(used.subtracting(Set(chart.types)))")
        expectTrue(used.contains("fairy"), "el dex actual sí trae Hada")
    }

    static func testClassicMatchups() {
        expectEqual(chart.factor(attacker: "water", defender: "fire"), 2)
        expectEqual(chart.factor(attacker: "fire", defender: "water"), 0.5)
        expectEqual(chart.factor(attacker: "fire", defender: "grass"), 2)
        expectEqual(chart.factor(attacker: "grass", defender: "water"), 2)
        expectEqual(chart.factor(attacker: "electric", defender: "water"), 2)
        expectEqual(chart.factor(attacker: "normal", defender: "normal"), 1)
    }

    static func testDualTypeDefendersMultiply() {
        // Charizard es fuego/volador: roca le entra x2 por cada mitad.
        expectEqual(chart.factor(attacker: "rock", defender: ["fire", "flying"]), 4)
        // Agua contra fuego/tierra: x2 y x2.
        expectEqual(chart.factor(attacker: "water", defender: ["fire", "ground"]), 4)
        // Planta contra agua (x2) y volador (x0,5) se compensan.
        expectEqual(chart.factor(attacker: "grass", defender: ["water", "flying"]), 1)
    }

    static func testAttackerPicksItsBestType() {
        // Bulbasaur (planta/veneno) contra agua: planta x2 manda sobre veneno x1.
        let matchup = chart.matchup(attacker: ["grass", "poison"], defender: ["water"])
        expectEqual(matchup.multiplier, 2, accuracy: 0.001)
        expectEqual(matchup.attacking, "grass")
    }

    static func testImmunityFallsToTheFloor() {
        // Normal no hace nada a Fantasma: sin suelo, el combate se atascaría.
        let matchup = chart.matchup(attacker: ["normal"], defender: ["ghost"])
        expectEqual(matchup.raw, 0)
        expectTrue(matchup.isImmune)
        expectEqual(matchup.multiplier, GameRules.minimumDamageMultiplier, accuracy: 0.001)
        expectEqual(matchup.label, "Inmune · daño mínimo")
    }

    static func testMultiplierIsBounded() {
        for attacker in chart.types {
            for defenderA in chart.types {
                for defenderB in chart.types {
                    let matchup = chart.matchup(attacker: [attacker], defender: [defenderA, defenderB])
                    expectTrue(
                        matchup.multiplier >= GameRules.minimumDamageMultiplier
                            && matchup.multiplier <= GameRules.maximumDamageMultiplier,
                        "\(attacker) contra \(defenderA)/\(defenderB) da \(matchup.multiplier)"
                    )
                }
            }
        }
    }

    static func testRealPokemonMatchups() {
        func matchup(_ attacker: Int, _ defender: Int) -> Double {
            chart.matchup(attacker: dex.require(attacker).types, defender: dex.require(defender).types).multiplier
        }
        expectEqual(matchup(7, 4), 2, accuracy: 0.001, "Squirtle contra Charmander")
        expectEqual(matchup(4, 7), 0.5, accuracy: 0.001, "Charmander contra Squirtle")
        expectEqual(matchup(4, 1), 2, accuracy: 0.001, "Charmander contra Bulbasaur")
        expectEqual(matchup(25, 130), 4, accuracy: 0.001, "Pikachu contra Gyarados (agua/volador)")
        expectEqual(matchup(19, 92), GameRules.minimumDamageMultiplier, accuracy: 0.001, "Rattata contra Gastly")
        expectEqual(matchup(147, 35), GameRules.minimumDamageMultiplier, accuracy: 0.001, "Dratini contra Clefairy: Hada anula Dragón")
    }
}
