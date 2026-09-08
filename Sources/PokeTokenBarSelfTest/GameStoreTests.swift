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
}
