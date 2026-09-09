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
        // v2 → v3: los gimnasios arrancan de cero. Decidido explícitamente no
        // convalidar rango por tokens ya gastados: una partida en curso pierde
        // el acceso a raros y legendarios hasta ganar 2 y 8 medallas.
        // v6 → v7: la evolución pasa de derivarse de los tokens y la semilla a
        // ser un hecho escrito en el ejemplar. Se escribe la forma que el
        // jugador ya estaba viendo, así que su caja no cambia: la rama que le
        // tocó se queda, y de ahí en adelante la deciden sus victorias.
        if state.schemaVersion < 7 {
            let dex = Pokedex.shared
            state.box = state.box.map { captured in
                guard captured.evolvedForms.isEmpty else { return captured }
                var migrated = captured
                migrated.evolvedForms = Self.legacyPath(of: captured, pokedex: dex)
                return migrated
            }
        }
        // v7 → v8: abrir Kanto pasa a pedir también 50 especies de Johto
        // registradas. A quien ya la tenía abierta no se le cierra.
        if state.schemaVersion < 8 {
            // La liga que abre la región 2 y cuál es sale del catálogo: el id
            // dejó de poder escribirse a mano al invertir el orden de juego.
            for league in LeagueCatalog.shared.all {
                guard let region = league.reward.opensRegion,
                      state.leagues.wonIDs.contains(league.id)
                else { continue }
                state.grandfatheredRegions.insert(region)
            }
        }
        state.schemaVersion = GameState.currentSchemaVersion
        return state
    }

    /// El camino que la versión anterior habría dibujado: desde la forma
    /// capturada, tantos pasos como den sus tokens y con la rama que fijaba la
    /// semilla. Solo se usa para migrar.
    static func legacyPath(of captured: CapturedPokemon, pokedex: Pokedex) -> [Int] {
        guard let species = pokedex[captured.speciesID] else { return [] }
        let reached = EvolutionStage.stage(forTotalTokens: captured.tokensEarned).rawValue
        guard reached > species.stage else { return [] }

        var forms: [Int] = []
        var current = species
        var rng = SeededRandomProvider(seed: captured.evolutionSeed)
        while current.stage < reached {
            let options = current.evolvesInto.compactMap { pokedex[$0] }
            guard !options.isEmpty else { break }
            let next = options[rng.nextInt(in: 0...(options.count - 1))]
            forms.append(next.id)
            current = next
        }
        return forms
    }
}
