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
    /// Región recién abierta, para celebrarla. Puede pasar al ganar la liga o
    /// **al registrar la especie que faltaba**, que es lo bonito del requisito:
    /// el salto de región puede llegar en una captura.
    @Published public private(set) var lastRegion: RegionTransfer?
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
    /// Pestaña abierta del popover. Es un String a propósito: el store no
    /// tiene por qué conocer los tipos de la UI.
    @Published public var selectedTab: String = "combate"
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
    private let spawner: SpawnService
    /// Con qué reloj se leen las bandas de día y noche que deciden una rama.
    /// Inyectable porque si no, un test dependería de la hora a la que corre.
    private let calendar: Calendar
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
        let registered: Int
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
        rng: any RandomProvider = SystemRandomProvider(),
        calendar: Calendar = .current
    ) {
        self.pokedex = pokedex
        self.typeChart = typeChart
        self.gymCatalog = gymCatalog
        self.zoneCatalog = zoneCatalog
        self.milestoneCatalog = milestoneCatalog
        self.leagueCatalog = leagueCatalog
        self.file = file
        self.rng = rng
        self.calendar = calendar
        self.battle = BattleEngine(pokedex: pokedex)
        self.spawner = SpawnService(pokedex: pokedex, zones: zoneCatalog)
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
            kantoOpen: isOpen(region: "kanto"),
            isChampion: state.leagues.isChampion
        )
    }

    // MARK: - El barco entre regiones

    /// Lo que falta para pasar de región: la liga de la región anterior y un
    /// mínimo de su Pokédex registrada.
    ///
    /// En Oro y Plata a Kanto se va en barco desde Ciudad Olivo después del
    /// Alto Mando; el requisito de Pokédex es lo que hace que la región 1 haya
    /// que jugarla y no solo atravesarla. La liga se puede ganar igual: lo que
    /// espera es el barco, no el contenido.
    public struct RegionTransfer: Sendable {
        public let region: String
        /// Liga que hay que ganar para que el barco exista.
        public let league: League
        /// Región de la que se cuentan las especies.
        public let from: String
        public let registered: Int
        public let required: Int
        public let leagueWon: Bool
        /// Abierta por el requisito nuevo o por venir ya abierta de antes.
        public let isOpen: Bool

        public var name: String { region.capitalized }
        public var missingSpecies: Int { max(0, required - registered) }
        public var speciesMet: Bool { registered >= required }
    }

    /// Especies registradas de una región (por su generación de origen).
    public func registeredSpecies(of region: String) -> Int {
        state.registeredSpeciesIDs.reduce(into: 0) { total, id in
            if pokedex[id]?.homeRegion.lowercased() == region.lowercased() { total += 1 }
        }
    }

    public func transfer(to region: String) -> RegionTransfer? {
        guard let league = leagueCatalog.all.first(where: { $0.reward.opensRegion == region }) else { return nil }
        let previous = gymCatalog.regions.first ?? "johto"
        let registered = registeredSpecies(of: previous)
        let won = state.leagues.wonIDs.contains(league.id)
        let grandfathered = state.grandfatheredRegions.contains(region)
        return RegionTransfer(
            region: region,
            league: league,
            from: previous,
            registered: registered,
            required: GameRules.regionTransferSpecies,
            leagueWon: won,
            isOpen: grandfathered || (won && registered >= GameRules.regionTransferSpecies)
        )
    }

    /// Mira si alguna región se ha abierto y la deja lista para celebrar. Se
    /// llama al guardar porque el requisito se puede cumplir por dos caminos
    /// distintos y ninguno debería tener que acordarse.
    private func noteRegionOpenings() {
        for region in gymCatalog.regions.dropFirst() {
            guard let transfer = transfer(to: region), transfer.isOpen,
                  !state.celebratedRegions.contains(region)
            else { continue }
            state.celebratedRegions.insert(region)
            // Las partidas que ya la tenían abierta no reciben confeti por algo
            // que pasó hace semanas.
            guard !state.grandfatheredRegions.contains(region) else { continue }
            lastRegion = transfer
        }
    }

    public func dismissRegionCelebration() {
        lastRegion = nil
    }

    /// Si una región de gimnasios está abierta. La primera siempre lo está.
    public func isOpen(region: String) -> Bool {
        guard region != gymCatalog.regions.first else { return true }
        return transfer(to: region)?.isOpen ?? state.leagues.wonIDs.contains("johto")
    }

    public var unlockedZones: [Zone] { zoneCatalog.unlocked(zoneAccess) }

    /// Zona enfocada, si está puesta **y** abierta. Una zona que se enfocó y
    /// luego dejó de estar abierta no puede seguir mandando en el sorteo.
    public var focusedZone: Zone? {
        guard let id = state.settings.focusedZoneID, let zone = zoneCatalog[id], zoneAccess.opens(zone)
        else { return nil }
        return zone
    }

    /// Enfoca una zona abierta, o quita el enfoque con `nil`. El rival en curso
    /// se queda: enfocar no le quita el HP que ya le has hecho.
    public func focus(zoneID: String?) {
        guard let zoneID else {
            updateSettings { $0.focusedZoneID = nil }
            return
        }
        guard let zone = zoneCatalog[zoneID], zoneAccess.opens(zone), !spawner.focusPool(zone).isEmpty
        else { return }
        updateSettings { $0.focusedZoneID = zone.id }
    }

    /// Lo que se puede cazar en una zona y cuánto te falta de ahí, que es lo
    /// que hace visible si enfocarla sirve para algo: en una zona de 2 la que
    /// buscas sale en 2 apariciones, en una ruta de 46 no la vas a ver.
    public func focusSummary(_ zone: Zone) -> (pool: Int, missing: Int) {
        let pool = spawner.focusPool(zone)
        let owned = ownedFamilies
        let missing = pool.filter { !owned.contains(familyKey(baseFormID: $0.baseFormID, shiny: false)) }
        return (pool.count, missing.count)
    }

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
        if !isOpen(region: candidate.region) { return nil }
        return candidate
    }

    /// Qué bloquea el avance de gimnasios, si algo lo bloquea.
    public var gymGate: League? {
        guard let candidate = gymCatalog.next(defeated: state.gyms.defeatedIDs),
              !isOpen(region: candidate.region)
        else { return nil }
        return transfer(to: candidate.region)?.league
    }

    public func medalGyms() -> [Gym] { gymCatalog.medals(defeated: state.gyms.defeatedIDs) }

    /// Medallas contadas **por región**, que es como se leen: cada región tiene
    /// sus ocho. El total (0-16) sigue siendo el que mueve el rango y los
    /// requisitos de las zonas, y por eso no se reinicia al cambiar de región:
    /// las de Johto siguen contando en Kanto.
    public struct RegionMedals: Identifiable, Sendable {
        public let region: String
        public let earned: Int
        public let total: Int
        /// Si sus gimnasios ya se pueden afrontar.
        public let open: Bool
        /// Qué hay que ganar para abrirla, si está cerrada.
        public let gate: League?

        public var id: String { region }
        public var name: String { region.capitalized }
    }

    public var medalsByRegion: [RegionMedals] {
        let won = state.gyms.defeatedIDs
        return gymCatalog.regions.map { region in
            let gyms = gymCatalog.gyms(in: region)
            // La liga que abre esa región, si la hay: la primera está abierta
            // desde el principio y las siguientes esperan a un Alto Mando.
            let opener = leagueCatalog.all.first { $0.reward.opensRegion == region }
            let open = opener.map { state.leagues.wonIDs.contains($0.id) } ?? true
            return RegionMedals(
                region: region,
                earned: gyms.filter { won.contains($0.id) }.count,
                total: gyms.count,
                open: open,
                gate: open ? nil : opener
            )
        }
    }

    /// Cruce del compañero contra el Pokémon estrella del líder: son sus tipos
    /// reales, no el tema del gimnasio.
    // MARK: - Jefes

    /// Cruce de tipos contra cualquier jefe. Una sola implementación para las
    /// tres mecánicas: ver `BossOpponent`.
    public func matchup(against boss: some BossOpponent) -> TypeMatchup {
        guard state.settings.typeEffectivenessEnabled,
              let attacker = activeForm,
              let defender = pokedex[boss.opponentSpeciesID]
        else { return .neutral }
        return typeChart.matchup(attacker: attacker.types, defender: defender.types)
    }

    /// HP que le quita cada token. Cero = bloqueado: hace falta otro
    /// compañero, no más tokens.
    public func damagePerToken(against boss: some BossOpponent) -> Double {
        gymCombat.damagePerToken(
            matchup: matchup(against: boss).multiplier,
            absorption: boss.absorption,
            stage: stage
        )
    }

    public func isBlocked(against boss: some BossOpponent) -> Bool {
        damagePerToken(against: boss) <= 0
    }

    /// Qué le hace un evento entero a un jefe. Lo comparten los tres combates:
    /// lo que cambia entre ellos es qué pasa **cuando cae**, no la aritmética.
    private func hit(_ boss: some BossOpponent, hp: Int, tokens: Int) -> BossHit {
        gymCombat.apply(
            tokens: tokens,
            toHP: hp,
            matchup: matchup(against: boss).multiplier,
            absorption: boss.absorption,
            stage: stage
        )
    }

    /// Qué falta para que se abra el próximo gimnasio. Se cumple con lo que
    /// llegue antes de las dos condiciones.
    /// Lo que falta para que se abra el siguiente gimnasio. `capturesLeft` son
    /// **victorias**: cuentan las de líneas que ya tienes.
    public var gymTriggerProgress: (tokensLeft: Int, capturesLeft: Int) {
        (
            max(0, GameRules.gymTokenInterval - state.gyms.tokensSinceLastGym),
            max(0, GameRules.gymCaptureInterval - state.gyms.capturesSinceLastGym)
        )
    }

    /// El gimnasio que ya se puede retar, si hay alguno. Sigue disponible
    /// mientras no se gane: el requisito abre la puerta, no empuja dentro.
    public var availableGym: Gym? {
        guard state.gyms.current == nil,
              state.milestones.current == nil,
              state.leagues.current == nil,
              state.gyms.triggerIsMet(),
              let gym = nextGym
        else { return nil }
        return gym
    }

    /// Entra al gimnasio. Igual que `startLeague` y `startMilestone`: es el
    /// jugador el que decide cuándo, y mientras no entre sigue cazando.
    @discardableResult
    public func startGym(_ id: String) -> Bool {
        guard let gym = availableGym, gym.id == id else { return false }
        openGym(now: Date())
        persist()
        return state.gyms.current != nil
    }

    /// Se puede salir: el progreso contra el líder se pierde y el disparador
    /// sigue cumplido, así que se puede volver a entrar cuando convenga.
    public func abandonGym() {
        guard state.gyms.current != nil else { return }
        state.gyms.current = nil
        ensureEncounter()
        persist()
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
    public func bestCompanion(against boss: some BossOpponent) -> (group: BoxGroup, rate: Double)? {
        guard let defender = pokedex[boss.opponentSpeciesID] else { return nil }
        let typesEnabled = state.settings.typeEffectivenessEnabled
        let candidates = boxGroups.filter { $0.id != activeGroupID }
        let scored = candidates.map { group -> (group: BoxGroup, rate: Double) in
            let multiplier = typesEnabled
                ? typeChart.matchup(attacker: group.displayForm.types, defender: defender.types).multiplier
                : 1
            return (
                group,
                gymCombat.damagePerToken(matchup: multiplier, absorption: boss.absorption, stage: group.stage)
            )
        }
        guard let best = scored.max(by: { $0.rate < $1.rate }), best.rate > 0 else { return nil }
        return best
    }

    /// La escalera de progreso, derivada de los catálogos.
    public var ladder: [LadderStep] {
        ProgressLadder(
            zones: zoneCatalog,
            gyms: gymCatalog,
            milestones: milestoneCatalog,
            leagues: leagueCatalog,
            pokedex: pokedex
        ).steps(medals: medals, wonLeagues: state.leagues.wonIDs)
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

    /// A qué le estás pegando ahora mismo y con qué tasa. Existe porque la
    /// métrica se calculaba solo contra el salvaje, y con un jefe abierto no
    /// hay salvaje: mostraba "0 al salvaje" mientras el jefe recibía daño.
    public struct CurrentTarget: Sendable {
        public let label: String
        public let rate: Double
        public let matchup: TypeMatchup
        public let isBoss: Bool
    }

    public var currentTarget: CurrentTarget? {
        if let active = activeLeague {
            return CurrentTarget(
                label: active.member.name,
                rate: damagePerToken(against: active.member),
                matchup: matchup(against: active.member),
                isBoss: true
            )
        }
        if let active = activeMilestone {
            return CurrentTarget(
                label: pokedex[active.milestone.speciesID]?.localizedName ?? active.milestone.place,
                rate: damagePerToken(against: active.milestone),
                matchup: matchup(against: active.milestone),
                isBoss: true
            )
        }
        if let active = activeGym {
            return CurrentTarget(
                label: active.gym.leader,
                rate: damagePerToken(against: active.gym),
                matchup: matchup(against: active.gym),
                isBoss: true
            )
        }
        if let rival = rivalSpecies {
            return CurrentTarget(
                label: rival.localizedName,
                rate: wildDamagePerToken,
                matchup: currentMatchup,
                isBoss: false
            )
        }
        return nil
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
        boxFilter.apply(to: boxGroups) { [weak self] in self?.timesDefeated(familyOf: $0) ?? 0 }
    }

    /// La caja partida en tramos con cabecera según el orden activo.
    public var boxSections: [BoxSection] {
        BoxSection.build(filteredBoxGroups, sort: boxFilter.sort) { [weak self] in
            self?.timesDefeated(familyOf: $0) ?? 0
        }
    }

    /// Los 251 huecos, con su estado. Memoizada por el mismo motivo que la
    /// caja: la UI la pide en cada render.
    public var pokedexEntries: [PokedexEntry] {
        let key = DexCacheKey(
            captures: state.box.count,
            defeats: state.familyDefeats.count,
            stage: stage.rawValue,
            registered: state.registeredSpeciesIDs.count
        )
        if let cached = dexCache, cached.key == key { return cached.entries }
        let entries = PokedexEntry.build(
            pokedex: pokedex,
            boxGroups: boxGroups,
            familyDefeats: state.familyDefeats,
            registered: state.registeredSpeciesIDs
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
    /// Mueve la selección de la caja con el teclado. Devuelve el hueco nuevo
    /// para que la vista pueda hacerle scroll.
    @discardableResult
    public func moveBoxSelection(_ direction: BoxMove, columns: Int) -> String? {
        let next = BoxSection.move(direction, from: selectedBoxGroupID, in: boxSections, columns: columns)
        if let next { selectedBoxGroupID = next }
        return next
    }

    /// Equipa el hueco seleccionado. Es lo que hace Intro en la caja.
    @discardableResult
    public func sendSelectedToBattle() -> Bool {
        guard let id = selectedBoxGroupID,
              let group = boxGroups.first(where: { $0.id == id })
        else { return false }
        setActiveCompanion(group.representative.id)
        return true
    }

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
        selectedTab = "combate"
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

    /// Cierra la ficha abierta. El tamaño del HUD no se toca: lo decide el
    /// botón de plegar, no un clic en un sprite.
    public func closeDetail() {
        selectedBoxGroupID = nil
        inspectingRival = false
    }

    /// Pliega o despliega una sección del popover.
    public func toggleSection(_ id: String) {
        updateSettings { settings in
            if settings.collapsedSections.contains(id) {
                settings.collapsedSections.remove(id)
            } else {
                settings.collapsedSections.insert(id)
            }
        }
    }

    public func isCollapsed(_ id: String) -> Bool {
        state.settings.collapsedSections.contains(id)
    }

    /// Pliega el HUD a su tira de combate, que es lo que cierra la caja PC.
    public func collapseHUD() {
        selectedBoxGroupID = nil
        inspectingRival = false
        updateSettings { $0.hudSize = nil }
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
            state.encounter = battle.freshEncounter(rank: rank, access: zoneAccess, focus: focusedZone, using: &rng)
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

        guard let tokens = resolveOpenBosses(tokens: damage, now: event.timestamp) else {
            creditActiveCompanion(tokens: damage, now: event.timestamp)
            persist()
            return nil
        }

        // Se resuelve por rival dentro del motor: un evento grande puede
        // encadenar capturas y cambiar el cruce de tipos a mitad.
        let attackerTypes = activeForm?.types ?? []
        let typesEnabled = state.settings.typeEffectivenessEnabled
        let chart = typeChart
        let pokedex = pokedex
        let collection = collectionBonus
        // El gimnasio ya no se abre solo. Antes el evento se cortaba al
        // terminar un salvaje y el líder ocupaba su sitio; ahora queda
        // **disponible** y se entra cuando el jugador quiera, igual que una
        // liga o un hito. Un jefe que se impone y encima te come los tokens
        // cuando el cruce de tipos no da es un peaje, no un reto.

        let result = battle.apply(
            damage: tokens,
            to: state.encounter,
            totalTokensAfter: state.ledger.total,
            rank: rank,
            access: zoneAccess,
            focus: focusedZone,
            multiplier: { encounter in
                guard typesEnabled, !attackerTypes.isEmpty,
                      let defender = pokedex[encounter.speciesID]
                else { return 1 + collection }
                let matchup = chart.matchup(attacker: attackerTypes, defender: defender.types).multiplier
                return matchup + collection
            },
            using: &rng,
            now: event.timestamp
        )
        state.encounter = result.encounter
        collect(result.defeated, at: event.timestamp)

        // Al final y no al principio: si se acreditara antes, el compañero
        // podría evolucionar a mitad del evento y pegar con la etapa nueva, así
        // que el ritmo real no coincidiría con el que la UI acaba de mostrar.
        creditActiveCompanion(tokens: damage, now: event.timestamp)

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
    /// Si se puede capturar **otro** ejemplar de una línea que ya tienes.
    ///
    /// Solo las líneas que bifurcan, solo mientras falte alguna de sus ramas, y
    /// solo si los que ya tienes están al final de su evolución. Lo último es
    /// la secuencia: evolucionas el Eevee que tienes y entonces puede salir
    /// otro, en vez de acumular cinco Eevees sin evolucionar.
    public func acceptsAnother(baseFormID: Int, shiny: Bool) -> Bool {
        let line = pokedex.all.filter { $0.baseFormID == baseFormID }
        guard line.contains(where: { !BranchRules.branches(of: $0.id).isEmpty }) else { return false }
        guard line.contains(where: { !state.registeredSpeciesIDs.contains($0.id) }) else { return false }

        let mine = state.box.filter { pokedex[$0.speciesID]?.baseFormID == baseFormID && $0.isShiny == shiny }
        return mine.allSatisfy { evolution.options(for: $0).isEmpty }
    }

    public func ownsFamily(of speciesID: Int, shiny: Bool) -> Bool {
        guard let base = pokedex[speciesID]?.baseFormID else { return false }
        return ownedFamilies.contains(familyKey(baseFormID: base, shiny: shiny))
    }

    /// Siguiente forma de un capturado concreto, para su ficha.
    /// Ramas de un ejemplar, con su condición y si ya la tienes registrada.
    /// La ficha las canta para que la mecánica no sea adivinar.
    public struct BranchOption: Identifiable, Sendable {
        public let form: Pokemon
        public let condition: BranchCondition
        public let registered: Bool
        /// La que saldría si evolucionara ahora mismo.
        public let isNext: Bool

        public var id: Int { form.id }
    }

    public func branchOptions(for captured: CapturedPokemon) -> [BranchOption] {
        let current = evolution.currentForm(of: captured).id
        let rules = BranchRules.branches(of: current)
        guard !rules.isEmpty else { return [] }
        let now = evolution.branch(for: captured, defeatedTypes: lastDefeatedTypes, at: Date(), calendar: calendar)
        return rules.compactMap { rule in
            guard let form = pokedex[rule.form] else { return nil }
            return BranchOption(
                form: form,
                condition: rule.condition,
                registered: state.registeredSpeciesIDs.contains(form.id),
                isNext: now?.id == form.id
            )
        }
    }

    /// Si el ejemplar equipado ya tiene derecho a evolucionar.
    public var activeCanEvolve: Bool {
        guard let companion = state.activeCompanion else { return false }
        return evolution.canEvolve(companion)
    }

    /// Si la banda del reloj está decidiendo algo ahora mismo: el equipado
    /// puede evolucionar y su rama depende de la hora. Es cuando el indicador
    /// de día/noche de la barra de menú sirve para algo.
    public var clockDecidesNow: Bool {
        guard let companion = state.activeCompanion, evolution.canEvolve(companion) else { return false }
        return branchOptions(for: companion).contains {
            if case .clock = $0.condition { return true }
            return false
        }
    }

    public var isDaylight: Bool { ClockBand.isDaylight(at: Date(), calendar: calendar) }

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
            state.lastDefeatedSpeciesID = wild.speciesID
            state.familyDefeats[base, default: 0] += 1
            state.gyms.capturesSinceLastGym += 1
            creditCompanionWildDefeat()

            let key = familyKey(baseFormID: base, shiny: wild.isShiny)
            if owned.contains(key), !acceptsAnother(baseFormID: base, shiny: wild.isShiny) { continue }
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

            let needed: Int
            switch hit(member, hp: run.currentHP, tokens: remaining) {
            case .blocked:
                // El HP no se mueve, los tokens se gastan igual: es la regla.
                run.tokensSpent += remaining
                state.leagues.current = run
                return 0
            case .survived(let hp):
                run.currentHP = hp
                run.tokensSpent += remaining
                state.leagues.current = run
                return 0
            case .fell(let spent):
                needed = spent
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

        let needed: Int
        switch hit(milestone, hp: battleState.currentHP, tokens: tokens) {
        case .blocked:
            battleState.tokensSpent += tokens
            state.milestones.current = battleState
            return 0
        case .survived(let hp):
            battleState.currentHP = hp
            battleState.tokensSpent += tokens
            state.milestones.current = battleState
            return 0
        case .fell(let spent):
            needed = spent
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

    /// Abre el gimnasio: sortea su HP y deja el combate en curso. Privado
    /// porque la entrada pasa por `startGym`, que comprueba el requisito.
    private func openGym(now: Date) {
        guard state.gyms.current == nil, let gym = nextGym else { return }
        let hp = rng.nextInt(in: gym.hpRange)
        state.gyms.current = ActiveGymBattle(gymID: gym.id, maxHP: hp, startedAt: now)
        state.encounter = nil
    }

    /// Manda el evento contra el jefe que haya abierto, en orden. Devuelve los
    /// tokens que sobran si cae, o `nil` si el evento se consumió entero.
    ///
    /// Vivía dentro de `ingest` con la misma guarda escrita tres veces. Y
    /// además `ingest` se había hecho tan grande que el compilador de Swift
    /// 6.3.3 petaba generando su IR.
    private func resolveOpenBosses(tokens: Int, now: Date) -> Int? {
        var tokens = tokens
        if state.leagues.current != nil {
            tokens = resolveLeagueBattle(tokens: tokens, now: now)
            guard tokens > 0 else { return nil }
        }
        if state.milestones.current != nil {
            tokens = resolveMilestoneBattle(tokens: tokens, now: now)
            guard tokens > 0 else { return nil }
        }
        if state.gyms.current != nil {
            tokens = resolveGymBattle(tokens: tokens, now: now)
            guard tokens > 0 else { return nil }
        }
        return tokens
    }

    /// Aplica tokens al líder y devuelve los que sobren si cae. Si el cruce de
    /// tipos no basta, el HP no se mueve pero los tokens se gastan igual.
    @discardableResult
    private func resolveGymBattle(tokens: Int, now: Date) -> Int {
        guard var battleState = state.gyms.current, let gym = gymCatalog[battleState.gymID] else { return tokens }

        let needed: Int
        switch hit(gym, hp: battleState.currentHP, tokens: tokens) {
        case .blocked:
            battleState.tokensSpent += tokens
            state.gyms.current = battleState
            return 0
        case .survived(let hp):
            battleState.currentHP = hp
            battleState.tokensSpent += tokens
            state.gyms.current = battleState
            return 0
        case .fell(let spent):
            needed = spent
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
    private func creditActiveCompanion(tokens: Int, now: Date = Date()) {
        guard tokens > 0,
              let companionID = state.activeCompanion?.id,
              let index = state.box.firstIndex(where: { $0.id == companionID })
        else { return }
        state.box[index].tokensEarned += tokens
        resolveEvolutions(at: index, now: now)
    }

    /// Tipos del último salvaje vencido, que es lo que decide la rama.
    public var lastDefeatedTypes: [String] {
        guard let id = state.lastDefeatedSpeciesID, let species = pokedex[id] else { return [] }
        return species.types
    }

    /// Convierte el derecho a evolucionar en evolución, eligiendo rama con lo
    /// último vencido y con la hora. Es un bucle porque un evento enorme puede
    /// dar para dos saltos: los dos usan el mismo rival y la misma hora, que es
    /// el instante en que llegaron esos tokens.
    private func resolveEvolutions(at index: Int, now: Date) {
        let types = lastDefeatedTypes
        for _ in 0..<EvolutionStage.allCases.count {
            guard evolution.canEvolve(state.box[index]),
                  let next = evolution.branch(
                      for: state.box[index],
                      defeatedTypes: types,
                      at: now,
                      calendar: calendar
                  )
            else { return }
            state.box[index].evolvedForms.append(next.id)
            state.registeredSpeciesIDs.insert(next.id)
            groupCache = nil
            dexCache = nil
        }
    }

    // MARK: - Persistencia

    /// Guarda con debounce: una ráfaga de eventos escribe una sola vez.
    /// Apunta en el registro las formas que **han sido** de cada ejemplar: su
    /// especie de captura y todas las etapas por las que ha pasado hasta la
    /// actual. Se sincroniza al guardar en vez de en cada sitio que mueve la
    /// caja, para que ninguna ruta se lo pueda olvidar; y se calcula por el
    /// camino evolutivo, no por la forma visible, para que un evento enorme que
    /// salte dos umbrales de golpe no se deje la forma intermedia sin registrar.
    private func syncPokedexRegistry() {
        var registry = state.registeredSpeciesIDs
        for captured in state.box {
            registry.insert(captured.speciesID)
            for form in captured.evolvedForms { registry.insert(form) }
        }
        guard registry != state.registeredSpeciesIDs else { return }
        state.registeredSpeciesIDs = registry
        dexCache = nil
    }

    /// Estado que se calcula a partir del resto y se guarda: el registro de la
    /// Pokédex y las regiones abiertas. En un solo sitio, por el que pasan
    /// tanto el guardado en diferido como el inmediato.
    private func syncDerivedState() {
        syncPokedexRegistry()
        noteRegionOpenings()
    }

    private func persist() {
        syncDerivedState()
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

    /// Abre una región como si el jugador hubiera hecho las dos mitades: ganar
    /// la liga y registrar las especies que pide el barco. Solo para tests y
    /// para el smoke test, que necesitan Kanto abierta sin jugar Johto entero.
    public func debugOpenRegion(_ region: String) {
        guard let transfer = transfer(to: region) else { return }
        state.leagues.award(transfer.league.id)
        let ids = pokedex.all
            .filter { $0.homeRegion.lowercased() == transfer.from.lowercased() }
            .map(\.id)
            .sorted()
            .prefix(transfer.required)
        for id in ids { state.registeredSpeciesIDs.insert(id) }
        dexCache = nil
    }

    /// Apunta una forma en el registro de la Pokédex. Solo para tests.
    public func debugRegister(speciesID: Int) {
        state.registeredSpeciesIDs.insert(speciesID)
        dexCache = nil
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
        syncDerivedState()
        do {
            try file.save(state)
        } catch {
            NSLog("PokeTokenBar: no se pudo guardar el estado: \(error)")
        }
    }
}
