import Foundation
import PokeTokenBarCore

@MainActor
enum PokedexEntryTests: TestSuite {
    static let suiteName = "Pokédex completa"

    static let tests: [(String, () throws -> Void)] = [
        ("tiene los 251 huecos en orden", testAllEntries),
        ("sin nada, todo está sin ver", testEmptyState),
        ("cuenta la especie capturada y la forma que se ve", testCapturedAndDisplayedForm),
        ("lo vencido sin quedárselo queda como visto", testDefeatedButNotCaptured),
        ("el filtro recorta sin inventar huecos", testFilter),
        ("una forma que evolucionó se queda registrada", testEvolvedPastFormStaysRegistered),
        ("el contador nunca baja al evolucionar", testCounterNeverGoesDown),
        ("las ramas alternativas no son alcanzables, y se dice", testAlternateBranchesAreCounted),
    ]

    private static let dex = Pokedex.shared
    private static let evolution = EvolutionService()

    private static func captured(_ speciesID: Int, earned: Int = 0) -> CapturedPokemon {
        CapturedPokemon(speciesID: speciesID, isShiny: false, capturedAtTotalTokens: 0, evolutionSeed: 3, tokensEarned: earned)
    }

    /// Ivysaur era un hueco imposible: al pasar tu Bulbasaur de 1M de tokens
    /// se convertía en Venusaur, la Pokédex dejaba de contar a Ivysaur y —como
    /// no se pueden repetir líneas— ese hueco no se podía llenar nunca más.
    static func testEvolvedPastFormStaysRegistered() throws {
        let venusaur = build(box: [captured(1, earned: 5_000_000)], registered: [1, 2, 3])
        expectEqual(venusaur.first { $0.species.id == 2 }?.state, .registered, "Ivysaur sigue en la Pokédex")
        expectEqual(venusaur.first { $0.species.id == 3 }?.state, .captured, "Venusaur es lo que se ve")
        expectEqual(venusaur.first { $0.species.id == 1 }?.state, .captured, "y Bulbasaur es como se capturó")
        expectTrue(venusaur.filter(\.isCaptured).count >= 3, "los tres cuentan")

        // Sin registro, el hueco de en medio se pierde: es el bug de antes.
        let sinRegistro = build(box: [captured(1, earned: 5_000_000)])
        expectEqual(sinRegistro.first { $0.species.id == 2 }?.state, .unknown)
    }

    /// Un contador de colección que baja es un bug por definición.
    static func testCounterNeverGoesDown() throws {
        let store = GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 13)
        )
        store.chooseStarter(speciesID: 1)
        store.updateSettings { $0.typeEffectivenessEnabled = false }

        var peak = 0
        // 12 eventos de 150k: el inicial cruza los dos umbrales por el camino.
        for i in 0..<12 {
            store.ingest(UsageEvent(id: "e\(i)", inputTokens: 150_000, outputTokens: 0))
            let now = store.pokedexCaptured
            expectTrue(now >= peak, "la Pokédex bajó de \(peak) a \(now)")
            peak = max(peak, now)
        }
        expectTrue(store.activeTokensEarned > GameRules.stageTwoThreshold, "el inicial llegó a la etapa 2")
        let ids = Set(store.pokedexEntries.filter(\.isCaptured).map(\.species.id))
        expectTrue(ids.isSuperset(of: [1, 2, 3]), "y las tres formas de su línea están: \(ids.sorted())")
    }

    static func testAlternateBranchesAreCounted() {
        expectEqual(dex.registrableCount + dex.alternateBranchCount, 251)
        expectEqual(dex.alternateBranchCount, 9, "Eevee (4), Gloom, Poliwhirl, Slowpoke y Tyrogue (2)")
        expectTrue(dex.registrableCount < 251, "prometer 251 sería mentir")
    }

    private static func build(
        box: [CapturedPokemon] = [],
        defeats: [Int: Int] = [:],
        registered: Set<Int> = []
    ) -> [PokedexEntry] {
        PokedexEntry.build(
            pokedex: dex,
            boxGroups: BoxGroup.group(box, pokedex: dex, evolution: evolution),
            familyDefeats: defeats,
            registered: registered
        )
    }

    static func testAllEntries() {
        let entries = build()
        expectEqual(entries.count, 251)
        expectEqual(entries.map(\.species.id), Array(1...251))
    }

    static func testEmptyState() {
        let entries = build()
        expectTrue(entries.allSatisfy { $0.state == .unknown })
        expectEqual(entries.filter(\.isCaptured).count, 0)
    }

    static func testCapturedAndDisplayedForm() throws {
        // Un Squirtle capturado que ya es Wartortle llena los dos huecos, pero
        // Blastoise sigue vacío: marcar la línea entera contaría formas que no
        // has visto nunca.
        let entries = build(box: [captured(7, earned: 250_000)])
        expectEqual(try unwrap(entries.first { $0.species.id == 7 }).state, PokedexEntry.State.captured)
        expectEqual(try unwrap(entries.first { $0.species.id == 8 }).state, PokedexEntry.State.captured)
        expectEqual(try unwrap(entries.first { $0.species.id == 9 }).state, PokedexEntry.State.unknown, "Blastoise no")
        expectEqual(entries.filter(\.isCaptured).count, 2)
    }

    static func testDefeatedButNotCaptured() throws {
        // Le has ganado a la línea de Pidgey pero no se quedó: los tres huecos
        // de la línea salen como vistos, no como capturados.
        let entries = build(defeats: [16: 3])
        for id in [16, 17, 18] {
            let entry = try unwrap(entries.first { $0.species.id == id })
            expectEqual(entry.state, PokedexEntry.State.defeated, "#\(id)")
            expectEqual(entry.defeats, 3)
        }
        expectEqual(entries.filter(\.isCaptured).count, 0)
        expectEqual(entries.filter { $0.state != .unknown }.count, 3)
    }

    static func testFilter() throws {
        let entries = build(box: [captured(7)], defeats: [16: 1])
        var filter = PokedexFilter()

        filter.query = "squirtle"
        expectEqual(filter.apply(to: entries).map(\.species.id), [7])
        filter.query = "#150"
        expectEqual(filter.apply(to: entries).map(\.species.id), [150])

        filter = PokedexFilter()
        filter.onlyMissing = true
        let missing = filter.apply(to: entries)
        expectEqual(missing.count, 250, "solo el Squirtle está en la caja")
        expectFalse(missing.contains { $0.species.id == 7 })

        filter = PokedexFilter()
        filter.onlyCaptured = true
        expectEqual(filter.apply(to: entries).map(\.species.id), [7])

        filter = PokedexFilter()
        filter.generation = 2
        let gen2 = filter.apply(to: entries)
        expectEqual(gen2.count, 100)
        expectTrue(gen2.allSatisfy { $0.species.id >= 152 })

        filter = PokedexFilter()
        filter.types = ["dragon"]
        let dragons = filter.apply(to: entries)
        expectTrue(dragons.allSatisfy { $0.species.types.contains("dragon") })
        expectGreaterThan(dragons.count, 0)

        // Invariante: filtrar nunca inventa ni duplica huecos.
        for query in ["", "a", "999", "#", "no-existe"] {
            filter = PokedexFilter()
            filter.query = query
            let result = filter.apply(to: entries)
            expectTrue(result.count <= entries.count)
            expectEqual(Set(result.map(\.id)).count, result.count)
        }
    }
}
