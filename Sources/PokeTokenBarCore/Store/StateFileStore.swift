import Foundation

/// Lectura/escritura del estado en disco. Escritura atómica: nunca dejamos un
/// state.json a medias si la app muere mientras guarda.
public struct StateFileStore {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? AppPaths.stateDirectory.appendingPathComponent("state.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func load() -> GameState {
        guard let data = try? Data(contentsOf: url) else { return GameState() }
        do {
            var state = try Self.decoder.decode(GameState.self, from: data)
            state = Self.migrate(state)
            return state
        } catch {
            // Estado corrupto: lo apartamos en vez de perderlo en silencio.
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("PokeTokenBar: state.json ilegible (\(error)); movido a \(backup.lastPathComponent)")
            return GameState()
        }
    }

    public func save(_ state: GameState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(state)
        let temporary = directory.appendingPathComponent(".state.json.\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    /// v1 → v2: la evolución pasa de derivarse del histórico global a ser
    /// progreso propio de cada Pokémon (`tokensEarned`). El compañero que venía
    /// equipado es el que había estado ganando esos tokens, así que se le
    /// acredita lo acumulado desde su captura; el resto arranca de cero, que es
    /// lo que refleja la realidad de la partida.
    static func migrate(_ state: GameState) -> GameState {
        var state = state
        if state.schemaVersion < 2 {
            let activeID = state.activeCompanion?.id
            state.box = state.box.map { captured in
                guard captured.id == activeID else { return captured }
                var promoted = captured
                promoted.tokensEarned = max(0, state.ledger.total - captured.capturedAtTotalTokens)
                return promoted
            }
        }
        state.schemaVersion = GameState.currentSchemaVersion
        return state
    }
}
