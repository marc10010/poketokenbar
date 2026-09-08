import Combine
import Foundation

/// Fuente única de verdad del juego. Todo entra por `ingest(_:)`, que es
/// idempotente por `UsageEvent.id`, y sale por `@Published var state`.
@MainActor
public final class GameStore: ObservableObject {
    @Published public private(set) var state: GameState
    /// Última captura, para que la UI pueda celebrarla.
    @Published public private(set) var lastCapture: CapturedPokemon?

    public let pokedex: Pokedex
    private let file: StateFileStore
    private let battle: BattleEngine
    private let evolution: EvolutionService
    private var rng: any RandomProvider
    private var processedIDs: Set<String>
    private var saveTask: Task<Void, Never>?
    private struct GroupCacheKey: Equatable {
        let captures: Int
        let stage: Int
    }

    private var groupCache: (key: GroupCacheKey, groups: [BoxGroup])?

    public init(
        pokedex: Pokedex = .shared,
        file: StateFileStore = StateFileStore(),
        rng: any RandomProvider = SystemRandomProvider()
    ) {
        self.pokedex = pokedex
        self.file = file
        self.rng = rng
        self.battle = BattleEngine(pokedex: pokedex)
        self.evolution = EvolutionService(pokedex: pokedex)
        let loaded = file.load()
        self.state = loaded
        self.processedIDs = Set(loaded.processedEventIDs)
    }

    // MARK: - Derivados para la UI

    public var totalTokens: Int { state.ledger.total }
    public var monthTokens: Int { state.ledger.currentMonth }
    public var stage: EvolutionStage { .stage(forTotalTokens: totalTokens) }

    public var activeForm: Pokemon? {
        guard let companion = state.activeCompanion else { return nil }
        return evolution.currentForm(of: companion, totalTokens: totalTokens)
    }

    public var activeNextForm: Pokemon? {
        guard let companion = state.activeCompanion else { return nil }
        return evolution.nextForm(of: companion, totalTokens: totalTokens)
    }

    public var rivalSpecies: Pokemon? {
        guard let encounter = state.encounter else { return nil }
        return pokedex[encounter.speciesID]
    }

    public func form(of captured: CapturedPokemon) -> Pokemon {
        evolution.currentForm(of: captured, totalTokens: totalTokens)
    }

    /// Caja PC ordenada por captura más reciente.
    public var box: [CapturedPokemon] { state.box.sorted { $0.capturedAt > $1.capturedAt } }

    /// Caja apilada por forma visible, en orden Pokédex. Memoizada: agrupar
    /// recorre todas las capturas y la UI la pide en cada render.
    public var boxGroups: [BoxGroup] {
        let key = GroupCacheKey(captures: state.box.count, stage: stage.rawValue)
        if let cached = groupCache, cached.key == key { return cached.groups }
        let groups = BoxGroup.group(state.box, totalTokens: totalTokens, evolution: evolution)
        groupCache = (key, groups)
        return groups
    }

    /// Formas distintas conseguidas, ignorando la variante de color: es la
    /// métrica que tiene techo (251) y la que mide el progreso de verdad.
    public var speciesCaught: Int {
        Set(boxGroups.map(\.form.id)).count
    }

    /// Grupo que corresponde al compañero activo, para marcarlo en la UI.
    public var activeGroupID: String? {
        guard let companion = state.activeCompanion, let form = activeForm else { return nil }
        return "\(form.id)-\(companion.isShiny)"
    }

    // MARK: - Acciones

    public func chooseStarter(speciesID: Int) {
        guard state.box.isEmpty, let species = pokedex[speciesID], species.isBaseForm else { return }
        let starter = CapturedPokemon(speciesID: speciesID, isShiny: false, capturedAtTotalTokens: totalTokens)
        state.box.append(starter)
        state.activeCompanionID = starter.id
        ensureEncounter()
        persist()
    }

    public func setActiveCompanion(_ id: UUID) {
        guard state.box.contains(where: { $0.id == id }) else { return }
        state.activeCompanionID = id
        persist()
    }

    public func updateSettings(_ transform: (inout GameSettings) -> Void) {
        transform(&state.settings)
        persist()
    }

    /// Crea rival si no hay. Idempotente.
    @discardableResult
    public func ensureEncounter() -> WildEncounter? {
        guard state.hasStarter else { return nil }
        if state.encounter == nil || state.encounter?.isFainted == true {
            state.encounter = battle.freshEncounter(totalTokens: totalTokens, using: &rng)
        }
        return state.encounter
    }

    /// Punto de entrada de todas las `TokenSource`. Ignora eventos repetidos.
    @discardableResult
    public func ingest(_ event: UsageEvent) -> BattleResult? {
        guard !processedIDs.contains(event.id) else { return nil }
        processedIDs.insert(event.id)
        state.markProcessed(event.id)

        let damage = event.damage(countingCache: state.settings.countCacheTokens)
        state.ledger.record(tokens: damage, at: event.timestamp)

        // Sin inicial elegido acumulamos tokens pero no hay combate todavía.
        guard state.hasStarter else {
            persist()
            return nil
        }

        let result = battle.apply(
            damage: damage,
            to: state.encounter,
            totalTokensAfter: state.ledger.total,
            using: &rng,
            now: event.timestamp
        )
        state.encounter = result.encounter
        if !result.captures.isEmpty {
            state.box.append(contentsOf: result.captures)
            state.lastCaptureSpeciesID = result.captures.last?.speciesID
            lastCapture = result.captures.last
        }
        persist()
        return result
    }

    public func ingest(_ events: [UsageEvent]) {
        for event in events { _ = ingest(event) }
    }

    // MARK: - Persistencia

    /// Guarda con debounce: una ráfaga de eventos escribe una sola vez.
    private func persist() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { [file] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            do {
                try file.save(snapshot)
            } catch {
                NSLog("PokeTokenBar: no se pudo guardar el estado: \(error)")
            }
        }
    }

    public func flush() {
        saveTask?.cancel()
        do {
            try file.save(state)
        } catch {
            NSLog("PokeTokenBar: no se pudo guardar el estado: \(error)")
        }
    }
}
