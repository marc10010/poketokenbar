import Foundation
import PokeTokenBarCore

@MainActor
enum CollectionTests: TestSuite {
    static let suiteName = "Colección"

    static let tests: [(String, () throws -> Void)] = [
        ("una línea repetida no se captura", testRepeatedFamilyIsNotCaptured),
        ("tener a Wartortle bloquea al Squirtle", testEvolvedFormBlocksItsBaseForm),
        ("el shiny de una línea que tienes desbloquea su paleta", testShinyUnlocksThePalette),
        ("dos iguales en el mismo evento solo dejan uno", testTwoOfTheSameFamilyInOneEvent),
        ("las victorias se apuntan al compañero", testDefeatsCreditTheCompanion),
        ("alternar shiny solo va en los shiny", testShinyDisplayToggle),
        ("con una sola paleta se dibuja esa, diga lo que diga la preferencia", testStoredPreferenceCannotShowWhatYouLack),
        ("el aviso dice lo que de verdad va a pasar", testCaptureOutcomeMatchesWhatHappens),
    ]

    /// El aviso de la ficha del rival sale de aquí, así que tiene que decir lo
    /// mismo que hace `collect`. Decía "no se queda" también en las líneas que
    /// bifurcan y sí aceptan un segundo ejemplar.
    static func testCaptureOutcomeMatchesWhatHappens() throws {
        let store = primed()
        store.debugGrandfatherRegion("johto")

        // Línea nueva.
        expectEqual(store.captureOutcome(of: 43, shiny: false), GameStore.CaptureOutcome.newLine)
        store.debugCapture(speciesID: 43)                       // Oddish

        // Ya la tienes y todavía puede evolucionar: no se queda otro.
        expectEqual(store.captureOutcome(of: 43, shiny: false), GameStore.CaptureOutcome.repeated)
        func oddishEnLaCaja() -> Int {
            store.state.box.filter { store.pokedex[$0.speciesID]?.baseFormID == 43 }.count
        }
        let antes = oddishEnLaCaja()
        store.debugSetEncounter(wild(43, hp: 200))
        store.ingest(event("repetido", tokens: 200))
        expectEqual(oddishEnLaCaja(), antes, "no debería haberse quedado")

        // El shiny de una línea que tienes no es un hueco: es su paleta.
        expectEqual(store.captureOutcome(of: 43, shiny: true), GameStore.CaptureOutcome.newPalette)

        // Evolucionado hasta el final y con una rama sin registrar: sí se queda.
        let oddish = try unwrap(store.state.box.first { $0.speciesID == 43 })
        store.setActiveCompanion(oddish.id)
        store.ingest(event("sube", tokens: 1_200_000))
        let evolucionado = try unwrap(store.state.box.first { $0.id == oddish.id })
        expectTrue(
            [45, 182].contains(evolucionado.evolvedForms.last ?? 43),
            "el Oddish tiene que haber llegado a Vileplume o Bellossom: \(evolucionado.evolvedForms)"
        )
        expectEqual(store.captureOutcome(of: 43, shiny: false), GameStore.CaptureOutcome.anotherForTheBranch)

        let antesDeLaRama = oddishEnLaCaja()
        store.debugSetEncounter(wild(43, hp: 200))
        store.ingest(event("segunda-rama", tokens: 200))
        expectEqual(oddishEnLaCaja(), antesDeLaRama + 1, "el segundo de la rama sí se queda")
    }

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

    /// Un shiny de una línea que ya tienes no ocupa otro hueco: desbloquea su
    /// paleta en el ejemplar que tienes, que es lo que se pidió. Antes eran dos
    /// entradas de caja y la mitad de los 258 huecos eran duplicados de color.
    static func testShinyUnlocksThePalette() throws {
        let store = primed()
        store.debugSetEncounter(wild(19))
        store.ingest(event("normal", tokens: 100))
        let after = store.state.box.count
        let rattata = try unwrap(store.state.box.last { $0.speciesID == 19 })
        expectFalse(rattata.isShiny)
        expectFalse(store.canToggleShinyDisplay(rattata), "sin el shiny no hay nada que alternar")

        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny", tokens: 100))
        expectEqual(store.state.box.count, after, "no ocupa un hueco nuevo")

        let ahora = try unwrap(store.state.box.first { $0.id == rattata.id })
        expectTrue(ahora.isShiny, "el que tenías pasa a tener su paleta shiny")
        expectTrue(ahora.caughtNormal, "y conserva la normal")
        expectTrue(ahora.displaysShiny, "un shiny se enseña")
        expectTrue(store.canToggleShinyDisplay(ahora), "y con las dos ya se puede cambiar")

        // Y un segundo shiny no vuelve a hacer nada.
        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny-2", tokens: 100))
        expectEqual(store.state.box.count, after)
    }

    /// La preferencia guardada no manda sobre lo que tienes. Una partida que
    /// quedó con `prefersShiny = false` en un shiny sin su normal —el cambio de
    /// paleta no pedía tener las dos hasta que se arregló— seguiría dibujando
    /// un Pokémon que no está en la caja.
    static func testStoredPreferenceCannotShowWhatYouLack() {
        let soloShiny = CapturedPokemon(
            speciesID: 21,
            isShiny: true,
            capturedAtTotalTokens: 0,
            prefersShiny: false
        )
        expectFalse(soloShiny.caughtNormal)
        expectTrue(soloShiny.displaysShiny, "sin el normal se dibuja shiny aunque pida lo otro")

        var conLasDos = soloShiny
        conLasDos.caughtNormal = true
        expectFalse(conLasDos.displaysShiny, "con las dos, manda la preferencia")
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

    /// La paleta normal solo se puede pedir si **también** tienes el normal:
    /// con un shiny como único ejemplar de su línea, dibujarlo en normal
    /// enseñaría un Pokémon que no está en la caja.
    static func testShinyDisplayToggle() throws {
        let store = primed()

        // Primero solo el shiny de una línea nueva.
        store.debugSetEncounter(wild(19, shiny: true))
        store.ingest(event("shiny", tokens: 100))
        let shiny = try unwrap(store.state.box.last { $0.isShiny })
        expectTrue(shiny.displaysShiny, "de fábrica se muestra shiny")
        expectFalse(shiny.caughtNormal, "solo tienes la paleta shiny")
        expectTrue(!store.canToggleShinyDisplay(shiny), "sin el normal, no se puede cambiar")

        store.toggleShinyDisplay(shiny.id)
        expectTrue(
            try unwrap(store.state.box.first { $0.id == shiny.id }).displaysShiny,
            "y pedirlo no hace nada"
        )

        // Cazando el normal de la misma línea, ya sí: no entra otro hueco,
        // se le apunta la paleta que faltaba al que tienes.
        let antes = store.state.box.count
        store.debugSetEncounter(wild(19))
        store.ingest(event("normal", tokens: 100))
        expectEqual(store.state.box.count, antes, "la paleta no ocupa hueco")
        let conLasDos = try unwrap(store.state.box.first { $0.id == shiny.id })
        expectTrue(conLasDos.caughtNormal, "el normal se apunta en el que tienes")
        expectTrue(store.canToggleShinyDisplay(conLasDos))

        store.toggleShinyDisplay(shiny.id)
        expectFalse(try unwrap(store.state.box.first { $0.id == shiny.id }).displaysShiny, "ahora en normal")
        store.toggleShinyDisplay(shiny.id)
        expectTrue(try unwrap(store.state.box.first { $0.id == shiny.id }).displaysShiny, "y vuelta")

        // Uno del que solo tienes el normal no se puede "pintar" de shiny.
        let plain = try unwrap(store.state.box.first { !$0.isShiny })
        expectTrue(!store.canToggleShinyDisplay(plain))
        store.toggleShinyDisplay(plain.id)
        expectFalse(try unwrap(store.state.box.first { $0.id == plain.id }).displaysShiny)
    }
}
