import Foundation
import PokeTokenBarCore

@MainActor
enum ProgressLadderTests: TestSuite {
    static let suiteName = "Escalera de progreso"

    static let tests: [(String, () throws -> Void)] = [
        ("va en orden y sin escalones vacíos", testOrderAndContent),
        ("marca alcanzado según medallas y ligas", testReachedFlags),
        ("la puerta entre regiones está entre los dos tramos", testGateIsInTheMiddle),
        ("todo lo que abre algo aparece en la escalera", testEverythingIsAnnounced),
    ]

    private static let ladder = ProgressLadder()
    private static let zones = ZoneCatalog.shared
    private static let milestones = MilestoneCatalog.shared

    /// Los ids de las ligas no se escriben a mano: la puerta es la que abre la
    /// segunda región y el final la que da el título, y eso lo dice el
    /// catálogo. El test tenía "johto" y "kanto" puestos a mano y se rompió al
    /// invertir el orden de juego, que es exactamente lo que tenía que avisar.
    private static let gate = LeagueCatalog.shared.all.first { $0.reward.opensRegion != nil }
    private static let finalLeague = LeagueCatalog.shared.all.first { $0.reward == .champion }
    private static var gateStepID: String { "league-\(gate?.id ?? "")" }
    private static var finalStepID: String { "league-\(finalLeague?.id ?? "")" }
    private static var secondRegion: String { GymCatalog.shared.regions.dropFirst().first ?? "" }

    static func testOrderAndContent() {
        let steps = ladder.steps(medals: 0, wonLeagues: [])
        expectGreaterThan(steps.count, 10)
        for step in steps {
            expectFalse(step.unlocks.isEmpty, "\(step.id) no abre nada y no debería estar")
        }
        // Los escalones por medallas van de menos a más dentro de cada tramo.
        let primerTramo = steps.prefix { !$0.id.hasPrefix("league-") }
        let counts = primerTramo.compactMap { step -> Int? in
            if case .medals(let count) = step.requirement { return count }
            return nil
        }
        expectEqual(counts, counts.sorted())
    }

    static func testReachedFlags() throws {
        let gateID = try unwrap(gate?.id)
        let finalID = try unwrap(finalLeague?.id)

        let sinNada = ladder.steps(medals: 0, wonLeagues: [])
        expectTrue(try unwrap(sinNada.first).reached, "el primer escalón siempre está alcanzado")
        expectFalse(sinNada.contains { $0.id == gateStepID && $0.reached })

        let conPuerta = ladder.steps(medals: 8, wonLeagues: [gateID])
        expectTrue(try unwrap(conPuerta.first { $0.id == gateStepID }).reached)
        // Con la segunda región abierta pero 8 medallas, los de 9+ no están.
        expectFalse(conPuerta.contains { $0.id == "medals-12" && $0.reached })

        let campeon = ladder.steps(medals: 16, wonLeagues: [gateID, finalID])
        expectTrue(campeon.allSatisfy(\.reached), "con todo hecho, todo alcanzado")
    }

    static func testGateIsInTheMiddle() throws {
        let steps = ladder.steps(medals: 16, wonLeagues: [try unwrap(gate?.id), try unwrap(finalLeague?.id)])
        let gateIndex = try unwrap(steps.firstIndex { $0.id == gateStepID })
        let finalIndex = try unwrap(steps.firstIndex { $0.id == finalStepID })
        expectTrue(gateIndex < finalIndex, "la puerta va antes del final")

        // Antes de la puerta, hasta 8 medallas; después, de 9 en adelante.
        for step in steps[..<gateIndex] {
            if case .medals(let count) = step.requirement { expectTrue(count <= 8, "medals-\(count) antes de la puerta") }
        }
        for step in steps[(gateIndex + 1)..<finalIndex] {
            if case .medals(let count) = step.requirement { expectTrue(count >= 9, "medals-\(count) después de la puerta") }
        }
        expectTrue(
            try unwrap(steps[gateIndex].unlocks.first).contains("gimnasios de \(secondRegion.capitalized)"),
            "la puerta anuncia lo que abre"
        )
    }

    static func testEverythingIsAnnounced() {
        let steps = ladder.steps(medals: 16, wonLeagues: ["kanto", "johto"])
        let texto = steps.flatMap(\.unlocks).joined(separator: " | ")

        // Toda zona que no sea la inicial debe anunciarse en algún escalón.
        for zone in zones.all where zone.unlock.requiredMedals > 0 || zone.unlock.requiredRegion != nil || zone.unlock.requiresChampion {
            expectTrue(texto.contains(zone.name), "la zona \(zone.name) no se anuncia")
        }
        // Y todo legendario que no dependa de la Pokédex.
        for milestone in milestones.all where milestone.requiredSpecies == nil {
            let nombre = Pokedex.shared.require(milestone.speciesID).localizedName
            expectTrue(texto.contains(nombre), "el legendario \(nombre) no se anuncia")
        }
    }
}
