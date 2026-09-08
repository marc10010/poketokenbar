import Foundation
import PokeTokenBarCore

@MainActor
enum CollectionTests: TestSuite {
    static let suiteName = "Colección"

    static let tests: [(String, () throws -> Void)] = [
        ("una línea repetida no se captura", testRepeatedFamilyIsNotCaptured),
        ("tener a Wartortle bloquea al Squirtle", testEvolvedFormBlocksItsBaseForm),
        ("el shiny de una línea que tienes sí se queda", testShinyOfOwnedFamilyIsKept),
        ("dos iguales en el mismo evento solo dejan uno", testTwoOfTheSameFamilyInOneEvent),
        ("las victorias se apuntan al compañero", testDefeatsCreditTheCompanion),
        ("alternar shiny solo va en los shiny", testShinyDisplayToggle),
    ]

    private static func makeStore(seed: UInt64 = 4) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func event(_ id: String, tokens: Int) -> UsageEvent {
        UsageEvent(id: id, inputTokens: tokens, outputTokens: 0)
    }

    /// Deja al jugador con Squirtle y sin efectividad de tipos, para que el
    /// daño sea 1 a 1 y los combates duren lo que se dice.
    private static func primed(seed: UInt64 = 4) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: 7)
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        return store
    }

    private static func wild(_ speciesID: Int, hp: Int = 100, shiny: Bool = false) -> WildEncounter {
        WildEncounter(speciesID: speciesID, isShiny: shiny, rarity: .common, maxHP: hp)
    }

    static func testRepeatedFamilyIsNotCaptured() throws {
        let store = primed()
        store.debugSetEncounter(wild(19))
        store.ingest(event("rattata-1", tokens: 100))
        expectEqual(store.state.box.count, 2, "inicial + Rattata")
        expectEqual(store.timesDefeated(familyOf: 19), 1)

        store.debugSetEncounter(wild(19))
        store.ingest(event("rattata-2", tokens: 100))
        expectEqual(store.state.box.count, 2, "el segundo Rattata no se queda")
        expectEqual(store.timesDefeated(familyOf: 19), 2, "pero la victoria cuenta")
    }

    static func testEvolvedFormBlocksItsBaseForm() throws {
        let store = primed()
        // El Squirtle inicial evoluciona a Wartortle con sus propios tokens.
        store.debugSetEncounter(wild(19, hp: 1))
        store.ingest(event("sube", tokens: 250_000))
        expectEqual(store.activeForm?.id, 8, "Wartortle")

        let before = store.state.box.count
        store.debugSetEncounter(wild(7))               // Squirtle salvaje
        store.ingest(event("squirtle", tokens: 100))
        expectEqual(store.state.box.count, before, "ya tienes esa línea, en su forma evolucionada")
        expectEqual(store.timesDefeated(familyOf: 7), 1, "cuenta como victoria")

        // Y tampoco su etapa siguiente.
        store.debugSetEncounter(wild(9))               // Blastoise salvaje
        store.ingest(event("blastoise", tokens: 100))
        expectEqual(store.state.box.count, before, "Blastoise es la misma línea")
    }

    static func testShinyOfOwnedFamilyIsKept() throws {
        let store = primed()
        store.debugSetEncounter(wild(19))
        store.ingest(event("normal", tokens: 100))
        let after = store.state.box.count

        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny", tokens: 100))
        expectEqual(store.state.box.count, after + 1, "un shiny es otra cosa y sí se queda")
        expectTrue(try unwrap(store.state.box.last).isShiny)

        // Pero un segundo shiny de la misma línea ya no.
        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny-2", tokens: 100))
        expectEqual(store.state.box.count, after + 1)
    }

    static func testTwoOfTheSameFamilyInOneEvent() throws {
        let store = primed()
        let before = store.state.box.count
        // Un solo evento que tumba dos Rattata seguidos: el motor reporta dos
        // victorias y la caja solo debe quedarse con la primera.
        store.debugSetEncounter(wild(19, hp: 50))
        store.ingest(event("doble", tokens: 100_000))
        expectEqual(
            store.state.box.filter { $0.speciesID == 19 }.count,
            1,
            "un solo Rattata en la caja pase lo que pase"
        )
        expectGreaterThan(store.state.box.count, before)
    }

    static func testDefeatsCreditTheCompanion() throws {
        let store = primed()
        let companionID = try unwrap(store.state.activeCompanion).id
        store.debugSetEncounter(wild(19))
        store.ingest(event("v1", tokens: 100))
        store.debugSetEncounter(wild(19))
        store.ingest(event("v2", tokens: 100))

        let companion = try unwrap(store.state.box.first { $0.id == companionID })
        expectEqual(companion.wildDefeats, 2, "dos salvajes vencidos con él equipado")
        expectEqual(companion.gymsWon, 0)
    }

    static func testShinyDisplayToggle() throws {
        let store = primed()
        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny", tokens: 100))
        let shiny = try unwrap(store.state.box.last { $0.isShiny })
        expectTrue(shiny.displaysShiny, "de fábrica se muestra shiny")

        store.toggleShinyDisplay(shiny.id)
        expectFalse(try unwrap(store.state.box.first { $0.id == shiny.id }).displaysShiny, "ahora en normal")
        store.toggleShinyDisplay(shiny.id)
        expectTrue(try unwrap(store.state.box.first { $0.id == shiny.id }).displaysShiny, "y vuelta")

        // Un normal no se puede "pintar" de shiny.
        let plain = try unwrap(store.state.box.first { !$0.isShiny })
        store.toggleShinyDisplay(plain.id)
        expectFalse(try unwrap(store.state.box.first { $0.id == plain.id }).displaysShiny)
    }
}
