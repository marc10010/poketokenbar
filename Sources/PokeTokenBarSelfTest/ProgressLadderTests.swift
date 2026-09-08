import Foundation
import PokeTokenBarCore

@MainActor
enum ProgressLadderTests: TestSuite {
    static let suiteName = "Escalera de progreso"

    static let tests: [(String, () throws -> Void)] = [
        ("va en orden y sin escalones vacíos", testOrderAndContent),
        ("marca alcanzado según medallas y ligas", testReachedFlags),
        ("la puerta de Kanto está entre los dos tramos", testGateIsInTheMiddle),
        ("todo lo que abre algo aparece en la escalera", testEverythingIsAnnounced),
    ]

    private static let ladder = ProgressLadder()
    private static let zones = ZoneCatalog.shared
    private static let milestones = MilestoneCatalog.shared

    static func testOrderAndContent() {
        let steps = ladder.steps(medals: 0, wonLeagues: [])
        expectGreaterThan(steps.count, 10)
        for step in steps {
            expectFalse(step.unlocks.isEmpty, "\(step.id) no abre nada y no debería estar")
        }
        // Los escalones por medallas van de menos a más dentro de cada tramo.
        let johto = steps.prefix { !$0.id.hasPrefix("league-") }
        let counts = johto.compactMap { step -> Int? in
            if case .medals(let count) = step.requirement { return count }
            return nil
        }
        expectEqual(counts, counts.sorted())
    }

    static func testReachedFlags() throws {
        let sinNada = ladder.steps(medals: 0, wonLeagues: [])
        expectTrue(try unwrap(sinNada.first).reached, "el primer escalón siempre está alcanzado")
        expectFalse(sinNada.contains { $0.id == "league-johto" && $0.reached })

        let conJohto = ladder.steps(medals: 8, wonLeagues: ["johto"])
        expectTrue(try unwrap(conJohto.first { $0.id == "league-johto" }).reached)
        // Con Kanto abierta pero 8 medallas, los escalones de 9+ no están.
        expectFalse(conJohto.contains { $0.id == "medals-12" && $0.reached })

        let campeon = ladder.steps(medals: 16, wonLeagues: ["johto", "kanto"])
        expectTrue(campeon.allSatisfy(\.reached), "con todo hecho, todo alcanzado")
    }

    static func testGateIsInTheMiddle() throws {
        let steps = ladder.steps(medals: 16, wonLeagues: ["johto", "kanto"])
        let gate = try unwrap(steps.firstIndex { $0.id == "league-johto" })
        let final = try unwrap(steps.firstIndex { $0.id == "league-kanto" })
        expectTrue(gate < final, "la puerta va antes del final")

        // Antes de la puerta, nada de Kanto; después, nada de 8 medallas o menos.
        for step in steps[..<gate] {
            if case .medals(let count) = step.requirement { expectTrue(count <= 8, "medals-\(count) antes de la puerta") }
        }
        for step in steps[(gate + 1)..<final] {
            if case .medals(let count) = step.requirement { expectTrue(count >= 9, "medals-\(count) después de la puerta") }
        }
        expectTrue(
            try unwrap(steps[gate].unlocks.first).contains("gimnasios de Kanto"),
            "la puerta anuncia lo que abre"
        )
    }

    static func testEverythingIsAnnounced() {
        let steps = ladder.steps(medals: 16, wonLeagues: ["johto", "kanto"])
        let texto = steps.flatMap(\.unlocks).joined(separator: " | ")

        // Toda zona que no sea la inicial debe anunciarse en algún escalón.
        for zone in zones.all where zone.unlock.requiredMedals > 0 || zone.unlock.requiresKanto || zone.unlock.requiresChampion {
            expectTrue(texto.contains(zone.name), "la zona \(zone.name) no se anuncia")
        }
        // Y todo legendario que no dependa de la Pokédex.
        for milestone in milestones.all where milestone.requiredSpecies == nil {
            let nombre = Pokedex.shared.require(milestone.speciesID).localizedName
            expectTrue(texto.contains(nombre), "el legendario \(nombre) no se anuncia")
        }
    }
}
