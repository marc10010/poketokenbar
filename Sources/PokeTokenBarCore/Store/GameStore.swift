import Combine
import Foundation

/// Fuente única de verdad del juego. Todo entra por `ingest(_:)`, que es
/// idempotente por `UsageEvent.id`, y sale por `@Published var state`.
@MainActor
public final class GameStore: ObservableObject {
    @Published public private(set) var state: GameState
    /// Última captura, para que la UI pueda celebrarla.
    @Published public private(set) var lastCapture: CapturedPokemon?
    /// Liga recién ganada, para celebrarla.
    @Published public private(set) var lastLeague: League?
    /// Medalla recién ganada, mientras se celebra. Se limpia sola.
    @Published public private(set) var lastMedal: MedalCelebration?
    /// Búsqueda y filtros de la caja PC. No se persiste: es estado de consulta,
    /// y arrancar con un filtro puesto de la sesión anterior desconcierta.
    @Published public var boxFilter = BoxFilter()
    /// Ficha abierta de la caja, y si se está mirando la del rival. Estado de
    /// consulta: no se persiste.
    @Published public var selectedBoxGroupID: String?
    @Published public var selectedGymID: String?
    @Published public var selectedMilestoneID: String?
    /// Pokédex completa abierta, con su propio recorte de búsqueda.
    @Published public var showingPokedex = false
    @Published public var pokedexFilter = PokedexFilter()
    @Published public var selectedDexSpeciesID: Int?
    @Published public var inspectingRival = false

    public let pokedex: Pokedex
    public let typeChart: TypeChart
    public let gymCatalog: GymCatalog
    public let zoneCatalog: ZoneCatalog
    public let milestoneCatalog: MilestoneCatalog
    public let leagueCatalog: LeagueCatalog
    private let file: StateFileStore
    private let battle: BattleEngine
    private let evolution: EvolutionService
    private let gymCombat = GymCombat()
    private var rng: any RandomProvider
    private var processedIDs: Set<String>
    private var saveTask: Task<Void, Never>?
    private var celebrationTask: Task<Void, Never>?
    /// Solo el compañero equipado gana tokens, así que su progreso basta para
    /// invalidar la caché.
    private struct GroupCacheKey: Equatable {
        let captures: Int
        let activeEarned: Int
    }

    private var groupCache: (key: GroupCacheKey, groups: [BoxGroup])?

    private struct DexCacheKey: Equatable {
        let captures: Int
        let defeats: Int
        let stage: Int
    }

    private var dexCache: (key: DexCacheKey, entries: [PokedexEntry])?

    public init(
        pokedex: Pokedex = .shared,
        typeChart: TypeChart = .shared,
        gymCatalog: GymCatalog = .shared,
        zoneCatalog: ZoneCatalog = .shared,
        milestoneCatalog: MilestoneCatalog = .shared,
        leagueCatalog: LeagueCatalog = .shared,
        file: StateFileStore = StateFileStore(),
        rng: any RandomProvider = SystemRandomProvider()
    ) {
        self.pokedex = pokedex
        self.typeChart = typeChart
        self.gymCatalog = gymCatalog
        self.zoneCatalog = zoneCatalog
        self.milestoneCatalog = milestoneCatalog
        self.leagueCatalog = leagueCatalog
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

    /// Etapa del compañero equipado, según los tokens que ÉL ha ganado.
    public var stage: EvolutionStage {
        guard let companion = state.activeCompanion else { return .base }
        return evolution.stage(of: companion)
    }

    /// Tokens ganados por el compañero equipado: es su barra de progreso, no
    /// el histórico global del jugador.
    public var activeTokensEarned: Int { state.activeCompanion?.tokensEarned ?? 0 }

    public var activeForm: Pokemon? {
        guard let companion = state.activeCompanion else { return nil }
        return evolution.currentForm(of: companion)
    }

    public var activeNextForm: Pokemon? {
        guard let companion = state.activeCompanion else { return nil }
        return evolution.nextForm(of: companion)
    }

    // MARK: - Gimnasios

    public var medals: Int { state.gyms.medals }

    /// Qué zonas están abiertas. Kanto se abre **ganando el Alto Mando de
    /// Johto**, no acumulando medallas: la liga es la puerta entre regiones.
    public var zoneAccess: ZoneAccess {
        ZoneAccess(
            medals: medals,
            kantoOpen: state.leagues.kantoOpen,
            isChampion: state.leagues.isChampion
        )
    }

    public var unlockedZones: [Zone] { zoneCatalog.unlocked(zoneAccess) }

    /// Zonas donde vive una especie, con su estado de apertura.
    public func zones(for speciesID: Int) -> [(zone: Zone, open: Bool)] {
        zoneCatalog.zones(for: speciesID).map { ($0, zoneAccess.opens($0)) }
    }

    public func isAvailableInTheWild(_ speciesID: Int) -> Bool {
        zoneCatalog.isAvailable(speciesID, zoneAccess) || zoneCatalog.unassigned.contains(speciesID)
    }
    public var rank: TrainerRank { state.gyms.rank }

    // MARK: - Ligas

    public var activeLeague: (league: League, member: LeagueMember, run: ActiveLeagueRun)? {
        guard let run = state.leagues.current,
              let league = leagueCatalog[run.leagueID],
              let member = league.member(at: run.memberIndex)
        else { return nil }
        return (league, member, run)
    }

    public func availability(of league: League) -> LeagueAvailability {
        if state.leagues.wonIDs.contains(league.id) { return .won }
        if state.leagues.current != nil || state.gyms.current != nil || state.milestones.current != nil {
            return .busy
        }
        if let previous = leagueCatalog.previous(of: league), !state.leagues.wonIDs.contains(previous.id) {
            return .needsPreviousLeague(previous.name)
        }
        if medals < league.requiredMedals { return .needsMedals(league.requiredMedals - medals) }
        return .available
    }

    public func matchup(against member: LeagueMember) -> TypeMatchup {
        guard state.settings.typeEffectivenessEnabled,
              let attacker = activeForm,
              let defender = pokedex[member.signatureSpeciesID]
        else { return .neutral }
        return typeChart.matchup(attacker: attacker.types, defender: defender.types)
    }

    public func damagePerToken(against member: LeagueMember) -> Double {
        gymCombat.damagePerToken(
            matchup: matchup(against: member).multiplier,
            absorption: member.absorption,
            stage: stage
        )
    }

    public func isBlocked(against member: LeagueMember) -> Bool {
        damagePerToken(against: member) <= 0
    }

    @discardableResult
    public func startLeague(_ id: String) -> Bool {
        guard let league = leagueCatalog[id],
              availability(of: league).isAvailable,
              let first = league.member(at: 0)
        else { return false }
        let hp = rng.nextInt(in: first.hpRange)
        state.leagues.current = ActiveLeagueRun(leagueID: id, maxHP: hp)
        state.encounter = nil
        persist()
        return true
    }

    /// Abandonar **reinicia la tirada**: es un gauntlet, no cinco combates
    /// sueltos. Se recuperan los salvajes.
    public func abandonLeague() {
        guard state.leagues.current != nil else { return }
        state.leagues.current = nil
        ensureEncounter()
        persist()
    }

    // MARK: - Hitos legendarios

    public var activeMilestone: (milestone: Milestone, battle: ActiveBossBattle)? {
        guard let battle = state.milestones.current,
              let milestone = milestoneCatalog[battle.milestoneID]
        else { return nil }
        return (milestone, battle)
    }

    /// Por qué un hito está o no disponible. Se dice, no se deja en gris.
    public func availability(of milestone: Milestone) -> MilestoneAvailability {
        if state.milestones.defeatedIDs.contains(milestone.id) { return .defeated }
        if state.milestones.current != nil || state.gyms.current != nil { return .busy }
        if let zone = zoneCatalog[milestone.zoneID], !zoneAccess.opens(zone) {
            return .zoneClosed(zone.name)
        }
        if medals < milestone.extraMedals { return .needsMedals(milestone.extraMedals - medals) }
        if let required = milestone.requiredSpecies, pokedexCaptured < required {
            return .needsSpecies(required - pokedexCaptured)
        }
        return .available
    }

    /// Cruce del compañero contra el legendario del hito.
    public func matchup(against milestone: Milestone) -> TypeMatchup {
        guard state.settings.typeEffectivenessEnabled,
              let attacker = activeForm,
              let defender = pokedex[milestone.speciesID]
        else { return .neutral }
        return typeChart.matchup(attacker: attacker.types, defender: defender.types)
    }

    public func damagePerToken(against milestone: Milestone) -> Double {
        gymCombat.damagePerToken(
            matchup: matchup(against: milestone).multiplier,
            absorption: milestone.absorption,
            stage: stage
        )
    }

    public func isBlocked(against milestone: Milestone) -> Bool {
        damagePerToken(against: milestone) <= 0
    }

    /// Abre el hito. Solo uno a la vez, y nunca con un gimnasio en curso.
    @discardableResult
    public func startMilestone(_ id: String) -> Bool {
        guard let milestone = milestoneCatalog[id], availability(of: milestone).isAvailable else { return false }
        let hp = rng.nextInt(in: milestone.hpRange)
        state.milestones.current = ActiveBossBattle(milestoneID: id, maxHP: hp)
        state.encounter = nil
        persist()
        return true
    }

    /// Se puede abandonar: el progreso del legendario se pierde, pero el
    /// jugador recupera sus salvajes. Un hito que te secuestra la partida
    /// hasta ganarlo sería una trampa, no un reto.
    public func abandonMilestone() {
        guard state.milestones.current != nil else { return }
        state.milestones.current = nil
        ensureEncounter()
        persist()
    }

    /// Gimnasio abierto ahora mismo, si lo hay.
    public var activeGym: (gym: Gym, battle: ActiveGymBattle)? {
        guard let battle = state.gyms.current, let gym = gymCatalog[battle.gymID] else { return nil }
        return (gym, battle)
    }

    /// Próximo gimnasio por afrontar, **respetando la puerta de región**: los
    /// de Kanto no aparecen hasta ganar el Alto Mando de Johto. Sin esta
    /// puerta, la región sería solo una etiqueta.
    public var nextGym: Gym? {
        guard let candidate = gymCatalog.next(defeated: state.gyms.defeatedIDs) else { return nil }
        if candidate.region == "kanto", !state.leagues.kantoOpen { return nil }
        return candidate
    }

    /// Qué bloquea el avance de gimnasios, si algo lo bloquea.
    public var gymGate: League? {
        guard gymCatalog.next(defeated: state.gyms.defeatedIDs)?.region == "kanto",
              !state.leagues.kantoOpen
        else { return nil }
        return leagueCatalog["johto"]
    }

    public func medalGyms() -> [Gym] { gymCatalog.medals(defeated: state.gyms.defeatedIDs) }

    /// Cruce del compañero contra el Pokémon estrella del líder: son sus tipos
    /// reales, no el tema del gimnasio.
    public func matchup(against gym: Gym) -> TypeMatchup {
        guard state.settings.typeEffectivenessEnabled,
              let attacker = activeForm,
              let defender = pokedex[gym.signatureSpeciesID]
        else { return .neutral }
        return typeChart.matchup(attacker: attacker.types, defender: defender.types)
    }

    /// HP que le quita cada token al líder. Cero = bloqueado: hace falta otro
    /// compañero, no más tokens.
    public func gymDamagePerToken(for gym: Gym) -> Double {
        gymCombat.damagePerToken(
            matchup: matchup(against: gym).multiplier,
            absorption: gym.absorption,
            stage: stage
        )
    }

    public func isBlocked(against gym: Gym) -> Bool { gymDamagePerToken(for: gym) <= 0 }

    /// Qué falta para que se abra el próximo gimnasio. Se cumple con lo que
    /// llegue antes de las dos condiciones.
    public var gymTriggerProgress: (tokensLeft: Int, capturesLeft: Int) {
        (
            max(0, GameRules.gymTokenInterval - state.gyms.tokensSinceLastGym),
            max(0, GameRules.gymCaptureInterval - state.gyms.capturesSinceLastGym)
        )
    }

    public func hasMedal(_ gymID: String) -> Bool { state.gyms.defeatedIDs.contains(gymID) }

    /// Tokens que faltan para tumbar al líder. `nil` si está bloqueado.
    public func gymTokensNeeded(for gym: Gym, battle: ActiveGymBattle) -> Int? {
        gymCombat.tokensNeeded(
            for: battle.currentHP,
            matchup: matchup(against: gym).multiplier,
            absorption: gym.absorption,
            stage: stage
        )
    }

    /// Mejor compañero de la caja contra este líder, distinto del equipado. Es
    /// la información que convierte un bloqueo en una acción de un clic.
    public func bestCompanion(against gym: Gym) -> (group: BoxGroup, rate: Double)? {
        guard let defender = pokedex[gym.signatureSpeciesID] else { return nil }
        let typesEnabled = state.settings.typeEffectivenessEnabled
        let candidates = boxGroups.filter { $0.id != activeGroupID }
        let scored = candidates.map { group -> (group: BoxGroup, rate: Double) in
            let multiplier = typesEnabled
                ? typeChart.matchup(attacker: group.displayForm.types, defender: defender.types).multiplier
                : 1
            return (
                group,
                gymCombat.damagePerToken(matchup: multiplier, absorption: gym.absorption, stage: group.stage)
            )
        }
        guard let best = scored.max(by: { $0.rate < $1.rate }), best.rate > 0 else { return nil }
        return best
    }

    /// Bonus por colección: lo que suma tener Pokédex al daño contra salvajes.
    ///
    /// Existe porque hasta ahora la caja era decoración —solo contaba el
    /// equipado— y capturar solo subía un contador. Con esto capturar es
    /// inversión.
    ///
    /// **Solo cuenta contra salvajes, no contra jefes**: si contara, una
    /// Pokédex avanzada anularía la absorción de los gimnasios tardíos y los
    /// jefes dejarían de ser un problema de cobertura de tipos para ser uno de
    /// acumulación, que es justo lo que se quería evitar.
    public var collectionBonus: Double {
        let ratio = Double(pokedexCaptured) / 251.0
        return min(GameRules.collectionBonusCap, max(0, ratio) * GameRules.collectionBonusCap)
    }

    /// Cruce de tipos del compañero activo contra el rival actual.
    public var currentMatchup: TypeMatchup {
        guard state.settings.typeEffectivenessEnabled,
              let attacker = activeForm,
              let defender = rivalSpecies
        else { return .neutral }
        return typeChart.matchup(attacker: attacker.types, defender: defender.types)
    }

    /// Daño por token contra el salvaje actual, bonus de colección incluido.
    /// Es lo que de verdad pasa, así que es lo que se muestra.
    public var wildDamagePerToken: Double {
        guard state.encounter != nil else { return 0 }
        let base = state.settings.typeEffectivenessEnabled ? currentMatchup.multiplier : 1
        return base + collectionBonus
    }

    public var rivalSpecies: Pokemon? {
        guard let encounter = state.encounter else { return nil }
        return pokedex[encounter.speciesID]
    }

    public func form(of captured: CapturedPokemon) -> Pokemon {
        evolution.currentForm(of: captured)
    }

    /// Caja PC ordenada por captura más reciente.
    public var box: [CapturedPokemon] { state.box.sorted { $0.capturedAt > $1.capturedAt } }

    /// Caja apilada por especie capturada, en orden Pokédex. Memoizada:
    /// agrupar recorre todas las capturas y la UI la pide en cada render.
    public var boxGroups: [BoxGroup] {
        let key = GroupCacheKey(captures: state.box.count, activeEarned: activeTokensEarned)
        if let cached = groupCache, cached.key == key { return cached.groups }
        let groups = BoxGroup.group(state.box, pokedex: pokedex, evolution: evolution)
        groupCache = (key, groups)
        return groups
    }

    /// Caja tras aplicar búsqueda y filtros.
    public var filteredBoxGroups: [BoxGroup] {
        boxFilter.apply(to: boxGroups)
    }

    /// Los 251 huecos, con su estado. Memoizada por el mismo motivo que la
    /// caja: la UI la pide en cada render.
    public var pokedexEntries: [PokedexEntry] {
        let key = DexCacheKey(captures: state.box.count, defeats: state.familyDefeats.count, stage: stage.rawValue)
        if let cached = dexCache, cached.key == key { return cached.entries }
        let entries = PokedexEntry.build(
            pokedex: pokedex,
            boxGroups: boxGroups,
            familyDefeats: state.familyDefeats
        )
        dexCache = (key, entries)
        return entries
    }

    public var filteredPokedexEntries: [PokedexEntry] {
        pokedexFilter.apply(to: pokedexEntries)
    }

    public var pokedexCaptured: Int { pokedexEntries.filter(\.isCaptured).count }
    public var pokedexSeen: Int { pokedexEntries.filter { $0.state != .unknown }.count }

    /// Tipos presentes en la caja, para no ofrecer filtros que no dan nada.
    public var typesInBox: [String] {
        Array(Set(boxGroups.flatMap(\.species.types))).sorted()
    }

    /// Formas distintas conseguidas, ignorando la variante de color: es la
    /// métrica que tiene techo (251) y la que mide el progreso de verdad.
    public var speciesCaught: Int {
        Set(boxGroups.map(\.species.id)).count
    }

    /// Grupo que corresponde al compañero activo, para marcarlo en la UI.
    public var activeGroupID: String? {
        guard let companion = state.activeCompanion else { return nil }
        return "\(companion.speciesID)-\(evolution.stage(of: companion).rawValue)-\(companion.isShiny)"
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

    /// Alterna entre la paleta shiny y la normal. Solo tiene efecto en un
    /// shiny de verdad: no se puede "pintar" uno normal.
    public func toggleShinyDisplay(_ capturedID: UUID) {
        guard let index = state.box.firstIndex(where: { $0.id == capturedID }), state.box[index].isShiny else { return }
        state.box[index].prefersShiny.toggle()
        groupCache = nil
        dexCache = nil
        persist()
    }

    /// Borra la partida entera y deja el juego como una instalación nueva:
    /// caja, medallas, contadores, estadísticas y el histórico de tokens.
    ///
    /// Los ajustes (HUD, tipos, fuentes) se conservan porque son preferencias,
    /// no progreso, y los ids de eventos ya procesados también: si se borraran,
    /// el consumo que ya se contabilizó podría volver a entrar como daño.
    public func resetGame() {
        selectedGymID = nil
        selectedMilestoneID = nil
        selectedDexSpeciesID = nil
        showingPokedex = false
        pokedexFilter.reset()
        let settings = state.settings
        let processed = state.processedEventIDs

        state = GameState()
        state.settings = settings
        state.processedEventIDs = processed
        groupCache = nil
        dexCache = nil
        lastCapture = nil
        lastMedal = nil
        selectedBoxGroupID = nil
        inspectingRival = false
        boxFilter.reset()
        flush()
    }

    public func updateSettings(_ transform: (inout GameSettings) -> Void) {
        transform(&state.settings)
        persist()
    }

    /// Crea rival si no hay. Idempotente.
    @discardableResult
    public func ensureEncounter() -> WildEncounter? {
        guard state.hasStarter else { return nil }
        // Con un jefe abierto no hay salvaje: ocupa ese hueco.
        guard state.gyms.current == nil,
              state.milestones.current == nil,
              state.leagues.current == nil
        else { return nil }
        if state.encounter == nil || state.encounter?.isFainted == true {
            state.encounter = battle.freshEncounter(rank: rank, access: zoneAccess, using: &rng)
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

        state.gyms.tokensSinceLastGym += damage

        // Con gimnasio abierto, el evento entero va contra el líder. Si cae,
        // los tokens que sobran siguen contra un salvaje nuevo.
        var tokens = damage
        if state.leagues.current != nil {
            tokens = resolveLeagueBattle(tokens: tokens, now: event.timestamp)
            guard tokens > 0 else {
                creditActiveCompanion(tokens: damage)
                persist()
                return nil
            }
        }
        if state.milestones.current != nil {
            tokens = resolveMilestoneBattle(tokens: tokens, now: event.timestamp)
            guard tokens > 0 else {
                creditActiveCompanion(tokens: damage)
                persist()
                return nil
            }
        }
        if state.gyms.current != nil {
            tokens = resolveGymBattle(tokens: tokens, now: event.timestamp)
            guard tokens > 0 else {
                creditActiveCompanion(tokens: damage)
                persist()
                return nil
            }
        }

        // Se resuelve por rival dentro del motor: un evento grande puede
        // encadenar capturas y cambiar el cruce de tipos a mitad.
        let attackerTypes = activeForm?.types ?? []
        let typesEnabled = state.settings.typeEffectivenessEnabled
        let chart = typeChart
        let pokedex = pokedex
        let collection = collectionBonus
        let progress = state.gyms
        let hasPendingGym = nextGym != nil
            && state.milestones.current == nil
            && state.leagues.current == nil

        let result = battle.apply(
            damage: tokens,
            to: state.encounter,
            totalTokensAfter: state.ledger.total,
            rank: rank,
            access: zoneAccess,
            multiplier: { encounter in
                guard typesEnabled, !attackerTypes.isEmpty,
                      let defender = pokedex[encounter.speciesID]
                else { return 1 + collection }
                let matchup = chart.matchup(attacker: attackerTypes, defender: defender.types).multiplier
                return matchup + collection
            },
            openGymAfterCapture: { captures in
                // El gimnasio se abre AL TERMINAR un salvaje, nunca a mitad.
                hasPendingGym && progress.triggerIsMet(extraCaptures: captures)
            },
            using: &rng,
            now: event.timestamp
        )
        state.encounter = result.encounter
        collect(result.defeated, at: event.timestamp)

        if result.stoppedForGym {
            openGym(now: event.timestamp)
            if result.remainingTokens > 0 {
                _ = resolveGymBattle(tokens: result.remainingTokens, now: event.timestamp)
            }
        }

        // Al final y no al principio: si se acreditara antes, el compañero
        // podría evolucionar a mitad del evento y pegar con la etapa nueva, así
        // que el ritmo real no coincidiría con el que la UI acaba de mostrar.
        creditActiveCompanion(tokens: damage)

        persist()
        return result
    }

    public func ingest(_ events: [UsageEvent]) {
        for event in events { _ = ingest(event) }
    }

    /// Líneas evolutivas ya conseguidas, separando shiny: un Wartortle
    /// bloquea al Squirtle, pero un Squirtle shiny sigue siendo otra cosa.
    public var ownedFamilies: Set<String> {
        Set(state.box.compactMap { captured in
            pokedex[captured.speciesID].map { familyKey(baseFormID: $0.baseFormID, shiny: captured.isShiny) }
        })
    }

    private func familyKey(baseFormID: Int, shiny: Bool) -> String { "\(baseFormID)-\(shiny)" }

    /// Veces que se ha vencido a esa línea en libertad, con captura o sin ella.
    /// Si ya tienes esa línea (en esa variante de color).
    public func ownsFamily(of speciesID: Int, shiny: Bool) -> Bool {
        guard let base = pokedex[speciesID]?.baseFormID else { return false }
        return ownedFamilies.contains(familyKey(baseFormID: base, shiny: shiny))
    }

    /// Siguiente forma de un capturado concreto, para su ficha.
    public func nextForm(of captured: CapturedPokemon) -> Pokemon? {
        evolution.nextForm(of: captured)
    }

    public func timesDefeated(familyOf speciesID: Int) -> Int {
        guard let base = pokedex[speciesID]?.baseFormID else { return 0 }
        return state.familyDefeats[base] ?? 0
    }

    /// Decide qué se queda de lo vencido. Una línea repetida **no** se captura:
    /// cuenta como victoria y nada más, así que la caja no acumula Squirtles
    /// cuando ya tienes un Wartortle.
    private func collect(_ defeated: [WildEncounter], at date: Date) {
        guard !defeated.isEmpty else { return }
        var owned = ownedFamilies

        for wild in defeated {
            let base = pokedex[wild.speciesID]?.baseFormID ?? wild.speciesID
            state.familyDefeats[base, default: 0] += 1
            state.gyms.capturesSinceLastGym += 1
            creditCompanionWildDefeat()

            let key = familyKey(baseFormID: base, shiny: wild.isShiny)
            guard !owned.contains(key) else { continue }
            owned.insert(key)

            let captured = CapturedPokemon(
                speciesID: wild.speciesID,
                isShiny: wild.isShiny,
                capturedAt: date,
                capturedAtTotalTokens: state.ledger.total
            )
            state.box.append(captured)
            state.lastCaptureSpeciesID = wild.speciesID
            lastCapture = captured
        }
    }

    private func creditCompanionWildDefeat() {
        guard let companionID = state.activeCompanion?.id,
              let index = state.box.firstIndex(where: { $0.id == companionID })
        else { return }
        state.box[index].wildDefeats += 1
    }

    /// Aplica tokens al miembro de liga en curso y encadena el siguiente sin
    /// salvajes en medio, que es lo que hace de esto un gauntlet. Al caer el
    /// último, la liga se gana y su recompensa abre región o corona.
    @discardableResult
    private func resolveLeagueBattle(tokens: Int, now: Date) -> Int {
        var remaining = tokens

        while remaining > 0 {
            guard var run = state.leagues.current,
                  let league = leagueCatalog[run.leagueID],
                  let member = league.member(at: run.memberIndex)
            else { return remaining }

            let matchup = matchup(against: member).multiplier
            guard damagePerToken(against: member) > 0 else {
                run.tokensSpent += remaining
                state.leagues.current = run
                return 0
            }

            let needed = gymCombat.tokensNeeded(
                for: run.currentHP,
                matchup: matchup,
                absorption: member.absorption,
                stage: stage
            ) ?? remaining

            guard remaining >= needed else {
                let hit = gymCombat.damage(
                    tokens: remaining,
                    matchup: matchup,
                    absorption: member.absorption,
                    stage: stage
                )
                run.currentHP -= min(run.currentHP, hit)
                run.tokensSpent += remaining
                state.leagues.current = run
                return 0
            }

            remaining -= needed
            run.tokensSpent += needed

            guard let next = league.member(at: run.memberIndex + 1) else {
                // Cae el último: liga ganada.
                state.leagues.current = nil
                state.leagues.award(league.id)
                lastLeague = league
                ensureEncounter()
                return remaining
            }

            run.memberIndex += 1
            run.currentHP = rng.nextInt(in: next.hpRange)
            state.leagues.current = ActiveLeagueRun(
                leagueID: run.leagueID,
                memberIndex: run.memberIndex,
                maxHP: run.currentHP,
                tokensSpent: run.tokensSpent,
                startedAt: run.startedAt
            )
        }

        return 0
    }

    /// Aplica tokens al legendario del hito y devuelve los que sobren si cae.
    /// Al vencerlo **sí se captura**: es la excepción a "un jefe no se queda",
    /// porque el objetivo del juego es la Pokédex.
    @discardableResult
    private func resolveMilestoneBattle(tokens: Int, now: Date) -> Int {
        guard var battleState = state.milestones.current,
              let milestone = milestoneCatalog[battleState.milestoneID]
        else { return tokens }

        let matchup = matchup(against: milestone).multiplier
        let rate = damagePerToken(against: milestone)
        guard rate > 0 else {
            battleState.tokensSpent += tokens
            state.milestones.current = battleState
            return 0
        }

        let needed = gymCombat.tokensNeeded(
            for: battleState.currentHP,
            matchup: matchup,
            absorption: milestone.absorption,
            stage: stage
        ) ?? tokens

        guard tokens >= needed else {
            let hit = gymCombat.damage(
                tokens: tokens,
                matchup: matchup,
                absorption: milestone.absorption,
                stage: stage
            )
            battleState.currentHP -= min(battleState.currentHP, hit)
            battleState.tokensSpent += tokens
            state.milestones.current = battleState
            return 0
        }

        state.milestones.current = nil
        state.milestones.award(battleState.milestoneID)
        captureLegendary(speciesID: milestone.speciesID, at: now)
        ensureEncounter()
        return tokens - needed
    }

    /// Mete el legendario en la caja. No pasa por la regla de líneas repetidas
    /// porque un hito solo se gana una vez y su línea no tiene nada más.
    private func captureLegendary(speciesID: Int, at date: Date) {
        let captured = CapturedPokemon(
            speciesID: speciesID,
            isShiny: false,
            capturedAt: date,
            capturedAtTotalTokens: state.ledger.total
        )
        state.box.append(captured)
        state.lastCaptureSpeciesID = speciesID
        lastCapture = captured
        groupCache = nil
        dexCache = nil
    }

    /// Abre el siguiente gimnasio: sortea su HP y deja el combate en curso.
    private func openGym(now: Date) {
        guard state.gyms.current == nil, let gym = nextGym else { return }
        let hp = rng.nextInt(in: gym.hpRange)
        state.gyms.current = ActiveGymBattle(gymID: gym.id, maxHP: hp, startedAt: now)
        state.encounter = nil
    }

    /// Aplica tokens al líder y devuelve los que sobren si cae. Si el cruce de
    /// tipos no basta, el HP no se mueve pero los tokens se gastan igual.
    @discardableResult
    private func resolveGymBattle(tokens: Int, now: Date) -> Int {
        guard var battleState = state.gyms.current, let gym = gymCatalog[battleState.gymID] else { return tokens }

        let rate = gymDamagePerToken(for: gym)
        guard rate > 0 else {
            battleState.tokensSpent += tokens
            state.gyms.current = battleState
            return 0
        }

        let needed = gymCombat.tokensNeeded(
            for: battleState.currentHP,
            matchup: matchup(against: gym).multiplier,
            absorption: gym.absorption,
            stage: stage
        ) ?? tokens

        guard tokens >= needed else {
            battleState.currentHP -= min(
                battleState.currentHP,
                gymCombat.damage(
                    tokens: tokens,
                    matchup: matchup(against: gym).multiplier,
                    absorption: gym.absorption,
                    stage: stage
                )
            )
            battleState.tokensSpent += tokens
            state.gyms.current = battleState
            return 0
        }

        // Cae el líder: medalla, sin captura, y contadores a cero.
        let rankBefore = rank
        battleState.currentHP = 0
        battleState.tokensSpent += needed
        state.gyms.current = nil
        state.gyms.award(gymID: gym.id)
        state.gyms.resetCounters()
        if let companionID = state.activeCompanion?.id,
           let index = state.box.firstIndex(where: { $0.id == companionID }) {
            state.box[index].gymsWon += 1
        }
        celebrate(gym: gym, rankBefore: rankBefore, now: now)
        // Un salvaje nuevo ya: si no, al cerrar el gimnasio sin tokens de
        // sobra el jugador se queda sin rival hasta el evento siguiente.
        ensureEncounter()
        return tokens - needed
    }

    /// Publica la celebración y la retira sola: una medalla es el hito del
    /// juego y merece más que un contador, pero no puede quedarse encima del
    /// combate para siempre.
    private func celebrate(gym: Gym, rankBefore: TrainerRank, now: Date) {
        let rankAfter = rank
        let rankUp = rankAfter > rankBefore ? rankAfter : nil
        let celebration = MedalCelebration(
            gym: gym,
            medals: medals,
            newRank: rankUp,
            unlocked: rankUp.map { new in Rarity.allCases.filter { $0.requiredRank == new } } ?? [],
            wonAt: now
        )
        lastMedal = celebration

        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(GameRules.medalCelebrationSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self?.lastMedal == celebration else { return }
            self?.lastMedal = nil
        }
    }

    /// Cierra la celebración antes de tiempo.
    public func dismissMedalCelebration() {
        celebrationTask?.cancel()
        lastMedal = nil
    }

    /// Acredita el consumo al compañero equipado: es lo que le hace subir de
    /// etapa, y por eso una evolución no se pierde al cambiar de compañero.
    private func creditActiveCompanion(tokens: Int) {
        guard tokens > 0,
              let companionID = state.activeCompanion?.id,
              let index = state.box.firstIndex(where: { $0.id == companionID })
        else { return }
        state.box[index].tokensEarned += tokens
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

    /// Fija los contadores del disparador. Solo para tests.
    public func debugSetGymCounters(tokens: Int, captures: Int) {
        state.gyms.tokensSinceLastGym = tokens
        state.gyms.capturesSinceLastGym = captures
    }

    /// Marca como derrotados los `count` primeros gimnasios. Solo para tests.
    public func debugDefeatGyms(upTo count: Int) {
        for gym in gymCatalog.all.prefix(count) { state.gyms.award(gymID: gym.id) }
    }

    /// Mete una captura en la caja sin combatir. Solo para tests.
    public func debugCapture(speciesID: Int, tokensEarned: Int = 0) {
        state.box.append(
            CapturedPokemon(
                speciesID: speciesID,
                isShiny: false,
                capturedAtTotalTokens: totalTokens,
                tokensEarned: tokensEarned
            )
        )
    }

    /// Da una liga por ganada. Solo para tests.
    public func debugWinLeague(_ id: String) {
        state.leagues.award(id)
    }

    /// Abre ya el siguiente gimnasio. Solo para tests.
    @discardableResult
    public func debugOpenNextGym() -> Gym? {
        openGym(now: Date())
        return activeGym?.gym
    }

    /// Fija el rival. Solo para tests: en el juego lo sortea `SpawnService`.
    public func debugSetEncounter(_ encounter: WildEncounter) {
        state.encounter = encounter
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
