import Foundation
import PokeTokenBarCore

@MainActor
enum GameStoreTests: TestSuite {
    static let suiteName = "GameStore"

    static let tests: [(String, () throws -> Void)] = [
        ("choosing a starter spawns the first rival", testChoosingAStarterSpawnsTheFirstRival),
        ("starter cannot be chosen twice", testStarterCannotBeChosenTwice),
        ("ingest is idempotent by event i d", testIngestIsIdempotentByEventID),
        ("cache tokens only count when enabled", testCacheTokensOnlyCountWhenEnabled),
        ("damage is applied to the rival and capture fills the box", testDamageIsAppliedToTheRivalAndCaptureFillsTheBox),
        ("tokens accumulate before choosing a starter", testTokensAccumulateBeforeChoosingAStarter),
        ("monthly history is keyed by month", testMonthlyHistoryIsKeyedByMonth),
        ("state persists across restarts including idempotency", testStatePersistsAcrossRestartsIncludingIdempotency),
        ("switching active companion only accepts owned pokemon", testSwitchingActiveCompanionOnlyAcceptsOwnedPokemon),
        ("processed event window is bounded", testProcessedEventWindowIsBounded),
        ("corrupt state file is quarantined not crashing", testCorruptStateFileIsQuarantinedNotCrashing),
        ("legacy settings decode with defaults", testLegacySettingsDecodeWithDefaults),
        ("species count ignores duplicates", testSpeciesCountIgnoresDuplicates),
        ("solo el equipado evoluciona", testOnlyTheActiveCompanionShowsEvolved),
        ("la evolución se queda al cambiar de compañero", testEvolutionSticksAfterSwitchingCompanion),
        ("la migración acredita al equipado", testMigrationCreditsTheEquippedCompanion),
        ("el multiplicador de tipos escala el daño real", testTypeMultiplierScalesDamage),
    ]

    private static func temporaryStateURL() -> URL {
        TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")
    }

    private static func makeStore(seed: UInt64 = 42) -> GameStore {
        GameStore(
            file: StateFileStore(url: temporaryStateURL()),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func event(_ id: String, input: Int = 100, output: Int = 100, cacheRead: Int = 0, at date: Date = Date()) -> UsageEvent {
        UsageEvent(id: id, inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead, timestamp: date)
    }

    static func testChoosingAStarterSpawnsTheFirstRival() {
        let store = makeStore()
        expectFalse(store.state.hasStarter)
        store.chooseStarter(speciesID: 155)
        expectEqual(store.state.box.count, 1)
        expectEqual(store.activeForm?.id, 155)
        expectNotNil(store.state.encounter)
    }

    static func testStarterCannotBeChosenTwice() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        store.chooseStarter(speciesID: 4)
        expectEqual(store.state.box.count, 1)
        expectEqual(store.state.box.first?.speciesID, 1)
    }

    static func testIngestIsIdempotentByEventID() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        let usage = event("msg_1", input: 500, output: 250)
        store.ingest(usage)
        store.ingest(usage)
        store.ingest(usage)
        expectEqual(store.totalTokens, 750)
        expectEqual(store.state.ledger.eventCount, 1)
    }

    static func testCacheTokensOnlyCountWhenEnabled() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        store.ingest(event("a", input: 10, output: 10, cacheRead: 5_000))
        expectEqual(store.totalTokens, 20)

        store.updateSettings { $0.countCacheTokens = true }
        store.ingest(event("b", input: 10, output: 10, cacheRead: 5_000))
        expectEqual(store.totalTokens, 5_040)
    }

    static func testDamageIsAppliedToTheRivalAndCaptureFillsTheBox() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        // Sin multiplicador de tipos para que 1 token siga siendo 1 HP exacto.
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        let rivalHP = try! unwrap(store.state.encounter).maxHP
        store.ingest(event("kill", input: rivalHP, output: 0))
        expectEqual(store.state.box.count, 2, "inicial + capturado")
        expectNotNil(store.lastCapture)
        expectEqual(store.state.encounter?.currentHP, store.state.encounter?.maxHP)
    }

    static func testTokensAccumulateBeforeChoosingAStarter() {
        let store = makeStore()
        store.ingest(event("pre", input: 1_000, output: 0))
        expectEqual(store.totalTokens, 1_000)
        expectNil(store.state.encounter)
        store.chooseStarter(speciesID: 7)
        expectNotNil(store.state.encounter)
    }

    static func testMonthlyHistoryIsKeyedByMonth() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        let january = ISO8601DateFormatter().date(from: "2026-01-15T10:00:00Z")!
        let february = ISO8601DateFormatter().date(from: "2026-02-02T10:00:00Z")!
        store.ingest(event("jan", input: 300, output: 0, at: january))
        store.ingest(event("feb", input: 700, output: 0, at: february))
        expectEqual(store.state.ledger.monthly["2026-01"], 300)
        expectEqual(store.state.ledger.monthly["2026-02"], 700)
        expectEqual(store.totalTokens, 1_000)
    }

    static func testStatePersistsAcrossRestartsIncludingIdempotency() throws {
        let url = temporaryStateURL()
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 9))
        store.chooseStarter(speciesID: 158)
        store.ingest(event("shared", input: 4_000, output: 0))
        store.flush()

        let reopened = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 9))
        expectEqual(reopened.totalTokens, 4_000)
        expectEqual(reopened.state.box.count, store.state.box.count)
        expectEqual(reopened.state.encounter?.currentHP, store.state.encounter?.currentHP)

        reopened.ingest(event("shared", input: 4_000, output: 0))
        expectEqual(reopened.totalTokens, 4_000, "el evento ya aplicado no vuelve a hacer daño")
    }

    static func testSwitchingActiveCompanionOnlyAcceptsOwnedPokemon() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        let rivalHP = try! unwrap(store.state.encounter).maxHP
        store.ingest(event("kill", input: rivalHP, output: 0))
        let captured = try! unwrap(store.state.box.last)
        store.setActiveCompanion(captured.id)
        expectEqual(store.state.activeCompanion?.id, captured.id)

        store.setActiveCompanion(UUID())
        expectEqual(store.state.activeCompanion?.id, captured.id)
    }

    static func testProcessedEventWindowIsBounded() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1)
        for index in 0..<(GameRules.processedEventWindow + 50) {
            store.ingest(event("e\(index)", input: 1, output: 0))
        }
        expectEqual(store.state.processedEventIDs.count, GameRules.processedEventWindow)
    }

    static func testCorruptStateFileIsQuarantinedNotCrashing() throws {
        let url = temporaryStateURL()
        try Data("{ no soy json valido".utf8).write(to: url)
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 1))
        expectEqual(store.totalTokens, 0)
        expectFalse(store.state.hasStarter)
    }

    /// Un state.json escrito antes de que existiera el HUD debe seguir
    /// cargando, con los ajustes nuevos en su valor por defecto.
    static func testLegacySettingsDecodeWithDefaults() throws {
        let url = temporaryStateURL()
        let legacy = """
        {
          "schemaVersion": 1,
          "ledger": { "total": 4321, "monthly": { "2026-09": 4321 }, "eventCount": 3 },
          "box": [],
          "processedEventIDs": [],
          "settings": { "countCacheTokens": true, "watchClaudeCodeTranscripts": true,
                        "ingestServerEnabled": true, "ingestPort": 8317 }
        }
        """
        try Data(legacy.utf8).write(to: url)
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 3))
        expectEqual(store.totalTokens, 4321, "no se pierde el histórico")
        expectEqual(store.state.settings.countCacheTokens, true, "se respeta lo que ya estaba")
        expectEqual(store.state.settings.hudEnabled, true)
        expectEqual(store.state.settings.hudCorner, HUDCorner.topRight)
        expectEqual(store.state.settings.hudOpacity, 0.9, accuracy: 0.0001)
        expectEqual(store.state.settings.hudLocked, false)
        expectNil(store.state.settings.hudFreeOrigin)
    }

    /// Capturar en cadena llena la caja de repetidos: el progreso se mide en
    /// especies (con techo), no en capturas (sin techo).
    static func testSpeciesCountIgnoresDuplicates() {
        let store = makeStore(seed: 11)
        store.chooseStarter(speciesID: 1)
        store.ingest(event("bulk", input: 2_000_000, output: 0))
        // Con gimnasios conectados, un evento así captura un par de salvajes y
        // el resto de los tokens se van al líder que se abre por el camino.
        expectGreaterThan(store.state.box.count, 1, "el evento grande captura varios")
        expectTrue(store.speciesCaught <= store.state.box.count)
        expectTrue(store.boxGroups.count <= store.state.box.count)
        expectEqual(store.boxGroups.reduce(0) { $0 + $1.count }, store.state.box.count, "no se pierde ninguna")
        expectTrue(store.speciesCaught <= 251)
    }

    /// Solo el compañero equipado gana tokens, así que solo él evoluciona; el
    /// resto de la caja sigue como se capturó.
    static func testOnlyTheActiveCompanionShowsEvolved() throws {
        let store = makeStore(seed: 5)
        store.chooseStarter(speciesID: 7)
        store.ingest(event("evoluciona", input: 400_000, output: 0))

        expectEqual(store.stage, EvolutionStage.one)
        expectEqual(store.activeTokensEarned, 400_000)
        expectEqual(store.activeForm?.id, 8, "Squirtle equipado se ve como Wartortle")

        let others = store.boxGroups.filter { $0.id != store.activeGroupID }
        expectGreaterThan(others.count, 0, "el evento captura rivales")
        for group in others {
            expectFalse(group.hasEvolved, "\(group.species.name) no debería salir evolucionado")
            expectEqual(group.representative.tokensEarned, 0)
        }
    }

    /// Lo que pidió el juego: cambias de compañero, subes al nuevo, y en la
    /// caja siguen saliendo los dos evolucionados.
    static func testEvolutionSticksAfterSwitchingCompanion() throws {
        let store = makeStore(seed: 21)
        store.chooseStarter(speciesID: 7)
        store.ingest(event("sube-squirtle", input: 250_000, output: 0))
        expectEqual(store.activeForm?.id, 8, "Wartortle")

        // Equipamos otro capturado y le damos sus propios tokens.
        let other = try unwrap(store.state.box.first { $0.id != store.state.activeCompanion?.id })
        store.setActiveCompanion(other.id)
        expectEqual(store.activeTokensEarned, 0, "el nuevo empieza de cero")
        store.ingest(event("sube-otro", input: 250_000, output: 0))
        expectEqual(store.stage, EvolutionStage.one)

        let squirtleGroup = try unwrap(store.boxGroups.first { $0.species.id == 7 })
        expectEqual(squirtleGroup.displayForm.id, 8, "el Squirtle sigue siendo Wartortle")
        expectEqual(squirtleGroup.representative.tokensEarned, 250_000, "su progreso no se toca")

        // Puede haber varios grupos de esa especie (uno por etapa): hay que
        // buscar el del ejemplar que equipamos, no el primero.
        let otherGroup = try unwrap(store.boxGroups.first { $0.representative.id == other.id })
        expectTrue(
            otherGroup.hasEvolved || store.pokedex.require(other.speciesID).evolvesInto.isEmpty,
            "el nuevo evoluciona salvo que su línea no tenga evolución"
        )
    }

    /// Migración v1 → v2: el estado viejo no tenía progreso por Pokémon. El
    /// compañero equipado es quien había estado ganando esos tokens.
    static func testMigrationCreditsTheEquippedCompanion() throws {
        let url = temporaryStateURL()
        let legacy = """
        {
          "schemaVersion": 1,
          "ledger": { "total": 362861, "monthly": { "2026-09": 362861 }, "eventCount": 40 },
          "box": [
            { "id": "AAAAAAAA-0000-0000-0000-000000000001", "speciesID": 7, "isShiny": false,
              "capturedAt": "2026-09-08T09:00:00Z", "capturedAtTotalTokens": 73608, "evolutionSeed": 11 },
            { "id": "AAAAAAAA-0000-0000-0000-000000000002", "speciesID": 204, "isShiny": false,
              "capturedAt": "2026-09-08T11:00:00Z", "capturedAtTotalTokens": 343030, "evolutionSeed": 12 }
          ],
          "activeCompanionID": "AAAAAAAA-0000-0000-0000-000000000001",
          "processedEventIDs": []
        }
        """
        try Data(legacy.utf8).write(to: url)
        let store = GameStore(file: StateFileStore(url: url), rng: SeededRandomProvider(seed: 1))

        expectEqual(store.state.schemaVersion, GameState.currentSchemaVersion)
        expectEqual(store.activeTokensEarned, 362_861 - 73_608, "al equipado se le acredita lo ganado desde su captura")
        expectEqual(store.activeForm?.id, 8, "sigue siendo Wartortle")

        let pineco = try unwrap(store.boxGroups.first { $0.species.id == 204 })
        expectEqual(pineco.representative.tokensEarned, 0)
        expectEqual(pineco.displayForm.id, 204, "el Pineco vuelve a ser Pineco, no Forretress")
    }

    /// El ledger cuenta tokens reales; el HP baja escalado por tipos. Son dos
    /// magnitudes distintas y no deben confundirse.
    static func testTypeMultiplierScalesDamage() throws {
        // Squirtle (agua) contra un rival de fuego: x2.
        let store = makeStore(seed: 77)
        store.chooseStarter(speciesID: 7)
        let fire = WildEncounter(speciesID: 4, isShiny: false, rarity: .common, maxHP: 40_000)
        store.debugSetEncounter(fire)
        expectEqual(store.currentMatchup.multiplier, 2, accuracy: 0.001)

        store.ingest(event("x2", input: 1_000, output: 0))
        expectEqual(store.totalTokens, 1_000, "el ledger cuenta tokens, no daño")
        expectEqual(store.state.encounter?.currentHP, 38_000, "1.000 tokens x2 = 2.000 HP")

        // Contra planta el agua es poco eficaz: x0,5.
        let grass = WildEncounter(speciesID: 1, isShiny: false, rarity: .common, maxHP: 40_000)
        store.debugSetEncounter(grass)
        expectEqual(store.currentMatchup.multiplier, 0.5, accuracy: 0.001)
        store.ingest(event("half", input: 1_000, output: 0))
        expectEqual(store.state.encounter?.currentHP, 39_500, "1.000 tokens x0,5 = 500 HP")

        // Con el interruptor apagado vuelve a ser 1 a 1.
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        expectEqual(store.currentMatchup.multiplier, 1, accuracy: 0.001)
        store.ingest(event("plain", input: 500, output: 0))
        expectEqual(store.state.encounter?.currentHP, 39_000)
    }
}
