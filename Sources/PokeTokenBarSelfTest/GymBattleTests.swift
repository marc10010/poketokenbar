import Foundation
import PokeTokenBarCore

@MainActor
enum GymBattleTests: TestSuite {
    static let suiteName = "Gimnasios · combate"

    static let tests: [(String, () throws -> Void)] = [
        ("queda disponible en vez de imponerse, y se puede salir", testGymBecomesAvailableNotForced),
        ("con el líder dentro, el evento entero es suyo", testWholeEventHitsTheLeader),
        ("derrotarlo da medalla y no captura", testDefeatGivesMedalNotCapture),
        ("la medalla se da una sola vez", testMedalIsAwardedOnce),
        ("con el cruce bloqueado el HP no se mueve", testBlockedGymDoesNotBudge),
        ("cambiar de compañero desbloquea el combate", testSwitchingCompanionUnblocks),
        ("los contadores se reinician al terminar", testCountersResetOnGymEnd),
        ("las medallas abren los tiers", testMedalsUnlockTiers),
        ("los tokens del gimnasio cuentan para el ledger y la evolución", testGymTokensStillCount),
        ("la medalla se celebra y dice qué desbloquea", testMedalCelebration),
        ("el ritmo es el que muestra la UI, sin evolucionar a mitad", testRateDoesNotChangeMidEvent),
        ("la métrica de daño apunta al líder, no al salvaje que no hay", testCurrentTargetIsTheBoss),
        ("las tres mecánicas de jefe comparten la fórmula", testEveryBossSharesTheFormula),
    ]

    private static let catalog = GymCatalog.shared

    private static func makeStore(seed: UInt64 = 3) -> GameStore {
        GameStore(
            file: StateFileStore(url: TemporaryFiles.uniqueDirectory().appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: seed)
        )
    }

    private static func event(_ id: String, tokens: Int) -> UsageEvent {
        UsageEvent(id: id, inputTokens: tokens, outputTokens: 0)
    }

    /// Deja al jugador con un salvaje de HP conocido y el disparador cumplido.
    private static func primed(seed: UInt64 = 3, starter: Int = 7, wildHP: Int = 10_000) -> GameStore {
        let store = makeStore(seed: seed)
        store.chooseStarter(speciesID: starter)
        store.updateSettings { $0.typeEffectivenessEnabled = false }
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: wildHP))
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        return store
    }

    /// Cumple el disparador y **entra**. Desde que el gimnasio es opcional,
    /// entrar es un acto del jugador, y los tests tienen que hacerlo también.
    @discardableResult
    private static func enterGym(_ store: GameStore, id: String = "abre") throws -> ActiveGymBattle {
        store.ingest(event(id, tokens: 10))
        let available = try unwrap(store.availableGym)
        expectTrue(store.startGym(available.id), "no se pudo entrar")
        return try unwrap(store.activeGym).battle
    }

    /// El gimnasio ya no se impone: al cumplirse el disparador queda
    /// **disponible** y el jugador sigue cazando hasta que decide entrar.
    static func testGymBecomesAvailableNotForced() throws {
        let store = primed(wildHP: 10_000)
        // El fixture ya deja el disparador cumplido, así que el líder está
        // disponible desde el principio. Lo que importa es que no entra solo.
        expectNil(store.activeGym, "no entra solo")
        expectEqual(store.availableGym?.id, "kanto-pewter", "pero espera")

        let rate = store.wildDamagePerToken
        let casi = Int(Double(10_000 - 1) / rate)
        store.ingest(event("roza", tokens: casi))
        expectNil(store.activeGym)
        expectTrue((store.state.encounter?.currentHP ?? 0) > 0, "el salvaje sigue vivo")

        store.ingest(event("remata", tokens: 10))
        let available = try unwrap(store.availableGym)
        expectEqual(available.id, "kanto-pewter", "el primero del orden: Brock")
        expectNil(store.activeGym, "pero no entra solo")
        expectNotNil(store.state.encounter, "y se sigue cazando")

        // Sigue disponible después de más eventos: la puerta no se cierra.
        store.ingest(event("mas", tokens: 50_000))
        expectEqual(store.availableGym?.id, "kanto-pewter")

        expectTrue(store.startGym("kanto-pewter"))
        let active = try unwrap(store.activeGym)
        expectNil(store.state.encounter, "ahora sí, no hay salvaje mientras hay líder")
        expectTrue(active.gym.hpRange.contains(active.battle.maxHP))
        expectNil(store.availableGym, "ya está dentro")

        // Y se puede salir, como de una liga o un hito.
        store.abandonGym()
        expectNil(store.activeGym)
        expectNotNil(store.state.encounter, "vuelve el salvaje")
        expectEqual(store.availableGym?.id, "kanto-pewter", "y el líder sigue esperando")
    }

    /// Con el líder dentro, el evento entero va contra él. El "sobrante de la
    /// captura" desapareció con el gimnasio automático: ya no hay un evento
    /// que se corte a mitad para meter al líder.
    static func testWholeEventHitsTheLeader() throws {
        let store = primed(wildHP: 10_000)
        store.updateSettings { $0.typeEffectivenessEnabled = true }
        let battle = try enterGym(store)
        expectEqual(battle.tokensSpent, 0, "entrar no gasta nada")

        // La tasa se pregunta, no se supone: Squirtle contra el Onix de Brock
        // es ×4 y su absorción es la más baja de las 16.
        let gym = try unwrap(store.activeGym).gym
        let rate = store.damagePerToken(against: gym)
        expectTrue(rate > 1, "agua contra roca/tierra pasa de sobra: \(rate)")

        store.ingest(event("al-lider", tokens: 100_000))
        let active = try unwrap(store.activeGym)
        expectEqual(active.battle.tokensSpent, 100_000, "el evento entero")
        expectEqual(
            active.battle.maxHP - active.battle.currentHP,
            Int((100_000.0 * rate).rounded()),
            "y al líder no le llega el bonus de colección"
        )
    }

    static func testDefeatGivesMedalNotCapture() throws {
        let store = primed(wildHP: 10)
        try enterGym(store)
        let active = try unwrap(store.activeGym)
        let boxBefore = store.state.box.count

        // De sobra para tumbarlo: sin efectividad de tipos, 1 HP por token
        // menos la absorción de 0,25 -> 0,75.
        store.ingest(event("gana", tokens: active.battle.currentHP * 2))

        expectNil(store.activeGym, "el gimnasio se cierra")
        expectEqual(store.medals, 1)
        expectEqual(store.rank, TrainerRank.novato, "una medalla todavía no sube de rango")
        expectEqual(store.state.gyms.defeated, ["kanto-pewter"])
        expectEqual(store.lastMedal?.gym.medal, "Medalla Roca")
        expectNotNil(store.state.encounter, "vuelve a haber salvaje")
        expectTrue(
            store.state.box.count >= boxBefore,
            "el líder no se captura: la caja solo puede crecer por los salvajes del sobrante"
        )
        expectFalse(
            store.state.box.contains { $0.speciesID == 95 },
            "Onix, el Pokémon del líder, no acaba en la caja"
        )
    }

    /// Un evento monstruoso puede encadenar gimnasios: tras cerrar el primero,
    /// el sobrante captura salvajes y esas capturas vuelven a cumplir el
    /// disparador. Lo que no puede pasar es dar dos veces la misma medalla.
    static func testMedalIsAwardedOnce() throws {
        let store = primed(wildHP: 10)
        let hp = try enterGym(store).maxHP
        store.ingest(event("bestial", tokens: hp * 20))

        expectGreaterThan(store.medals, 0)
        expectEqual(
            Set(store.state.gyms.defeated).count,
            store.state.gyms.defeated.count,
            "ninguna medalla repetida aunque el evento pase de sobra del HP"
        )
        expectEqual(store.state.gyms.defeated.first, "kanto-pewter", "y en orden")

        // El invariante, directo: otorgar dos veces el mismo gimnasio no suma.
        var progress = GymProgress()
        progress.award(gymID: "kanto-pewter")
        progress.award(gymID: "kanto-pewter")
        expectEqual(progress.medals, 1)
    }

    /// Con el cruce bloqueado el HP no se mueve por muchos tokens que entren, y
    /// los tokens se gastan igual: es un bloqueo, no un ahorro.
    static func testBlockedGymDoesNotBudge() throws {
        let store = makeStore(seed: 9)
        store.chooseStarter(speciesID: 7)
        store.debugOpenRegion("johto")     // los gimnasios de la región 2
        store.debugDefeatGyms(upTo: 15)
        let clair = try unwrap(store.debugOpenNextGym())
        expectEqual(clair.leader, "Clair", "la última del orden")

        // Pikachu (eléctrico) contra Kingdra (agua/dragón): ×2 al agua y ×0,5
        // al dragón se quedan en ×1, y con absorción 1,5 el progreso es cero.
        store.debugCapture(speciesID: 25)
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.isBlocked(against: clair))

        let before = try unwrap(store.activeGym).battle
        store.ingest(event("inútil", tokens: 400_000))
        let after = try unwrap(store.activeGym).battle

        expectEqual(after.currentHP, before.currentHP, "ni un HP")
        expectEqual(after.tokensSpent, before.tokensSpent + 400_000, "pero los tokens se gastaron")
        expectEqual(store.medals, 15, "y no hay medalla")
        expectEqual(store.totalTokens, 400_000, "el ledger los cuenta igual")
    }

    static func testSwitchingCompanionUnblocks() throws {
        let store = makeStore(seed: 11)
        store.chooseStarter(speciesID: 7)
        store.debugOpenRegion("johto")
        store.debugDefeatGyms(upTo: 15)    // siguiente: Clair, absorción 1,5
        let clair = try unwrap(store.nextGym)

        // Squirtle (agua) contra Kingdra (agua/dragón) hace ×0,5: bloqueado.
        expectTrue(store.isBlocked(against: clair), "agua contra agua/dragón no pasa 1,5")
        expectEqual(store.damagePerToken(against: clair), 0, accuracy: 0.001)

        // Contra Kingdra solo pasa el dragón: hielo y planta se quedan en ×1
        // porque el dragón resiste justo lo que al agua le duele. Dratini hace
        // ×2 y deja 2 - 1,5 = 0,5 por token. Es la salida que ofrece la ficha.
        store.debugCapture(speciesID: 147)                // Dratini
        let dratini = try unwrap(store.state.box.last)
        store.setActiveCompanion(dratini.id)
        expectFalse(store.isBlocked(against: clair), "dragón contra agua/dragón sí pasa")
        expectEqual(store.damagePerToken(against: clair), 0.5, accuracy: 0.001)

        // Y volver al Squirtle vuelve a bloquear, sin tocar el daño ya hecho.
        let squirtle = try unwrap(store.state.box.first)
        store.setActiveCompanion(squirtle.id)
        expectTrue(store.isBlocked(against: clair))
    }

    static func testCountersResetOnGymEnd() throws {
        let store = primed(wildHP: 10)
        try enterGym(store)
        let active = try unwrap(store.activeGym)
        expectGreaterThan(store.state.gyms.tokensSinceLastGym, GameRules.gymTokenInterval - 1)

        // Justo los tokens que hacen falta: sin sobrante no hay capturas
        // posteriores, así que los contadores quedan limpios de verdad.
        let needed = try unwrap(
            GymCombat().tokensNeeded(
                for: active.battle.currentHP,
                matchup: 1,
                absorption: active.gym.absorption
            )
        )
        store.ingest(event("justo", tokens: needed))

        expectEqual(store.medals, 1)
        expectEqual(store.state.gyms.tokensSinceLastGym, 0, "a cero al TERMINAR, no al abrir")
        expectEqual(store.state.gyms.capturesSinceLastGym, 0)
        expectNil(store.activeGym, "no se encadena otro gimnasio de inmediato")
        expectNotNil(store.state.encounter, "y vuelve a haber salvaje")
    }

    static func testMedalsUnlockTiers() {
        let store = makeStore(seed: 5)
        store.chooseStarter(speciesID: 7)
        expectEqual(store.rank, TrainerRank.novato)
        expectEqual(SpawnService().availableTiers(rank: store.rank), [.common, .uncommon])

        store.debugDefeatGyms(upTo: 2)
        expectEqual(store.medals, 2)
        expectEqual(store.rank, TrainerRank.entrenador)
        expectTrue(SpawnService().availableTiers(rank: store.rank).contains(.rare))
        expectFalse(SpawnService().availableTiers(rank: store.rank).contains(.legendary))

        store.debugDefeatGyms(upTo: 8)
        expectEqual(store.rank, TrainerRank.ace)
        expectFalse(
            SpawnService().availableTiers(rank: store.rank).contains(.legendary),
            "los legendarios pasaron a ser hitos: el rango As ya no los saca en libertad"
        )
    }

    /// Con un gimnasio abierto no hay salvaje, así que `wildDamagePerToken` es
    /// 0: la métrica tiene que hablar del líder o dice que no haces daño
    /// mientras se lo estás haciendo.
    static func testCurrentTargetIsTheBoss() throws {
        let store = primed(wildHP: 10)
        let wild = try unwrap(store.currentTarget)
        expectTrue(!wild.isBoss, "sin gimnasio, el objetivo es el salvaje")

        try enterGym(store)
        let gym = try unwrap(store.activeGym).gym
        expectEqual(store.wildDamagePerToken, 0, accuracy: 0.0001, "no hay salvaje al que pegar")

        let target = try unwrap(store.currentTarget)
        expectTrue(target.isBoss)
        expectEqual(target.label, gym.leader)
        expectEqual(target.rate, store.damagePerToken(against: gym), accuracy: 0.0001)
        expectTrue(target.rate > 0, "y la tasa del líder no es cero")
    }

    /// Gimnasio, liga y hito pasan por la **misma** aritmética. Tenían tres
    /// copias de `matchup`, `damagePerToken` e `isBlocked`, y arreglar la
    /// fórmula era acordarse de los tres sitios. Si alguien vuelve a darle a
    /// una mecánica su propia cuenta, esto se pone rojo.
    static func testEveryBossSharesTheFormula() throws {
        let store = primed()
        store.updateSettings { $0.typeEffectivenessEnabled = true }
        let combat = GymCombat()

        let gym = try unwrap(GymCatalog.shared.all.first)
        let member = try unwrap(LeagueCatalog.shared.all.first?.members.first)
        let milestone = try unwrap(MilestoneCatalog.shared.all.first)

        func check(_ boss: some BossOpponent, _ name: String) {
            let expected = combat.damagePerToken(
                matchup: store.matchup(against: boss).multiplier,
                absorption: boss.absorption,
                stage: store.stage
            )
            expectEqual(store.damagePerToken(against: boss), expected, accuracy: 0.0001, name)
            expectEqual(store.isBlocked(against: boss), expected <= 0, "\(name): bloqueado y tasa no coinciden")
        }

        check(gym, "gimnasio")
        check(member, "liga")
        check(milestone, "hito")
    }

    static func testGymTokensStillCount() throws {
        let store = primed(wildHP: 10)
        try enterGym(store)
        let earnedBefore = store.activeTokensEarned
        let totalBefore = store.totalTokens

        store.ingest(event("pega", tokens: 50_000))
        expectEqual(store.totalTokens, totalBefore + 50_000, "el ledger cuenta los tokens del gimnasio")
        expectEqual(store.activeTokensEarned, earnedBefore + 50_000, "y el compañero también evoluciona con ellos")
    }

    /// El compañero cobra los tokens DESPUÉS de resolver el combate. Si cobrara
    /// antes, un evento que le hace evolucionar le daría el bonus de etapa
    /// dentro del mismo evento y el ritmo real no sería el que la UI mostraba.
    static func testRateDoesNotChangeMidEvent() throws {
        let store = primed(wildHP: 10)
        try enterGym(store)
        let active = try unwrap(store.activeGym)
        let rateShown = store.damagePerToken(against: active.gym)
        expectEqual(rateShown, 0.75, accuracy: 0.001, "etapa base: 1 − 0,25 de absorción")

        // Un evento que evoluciona al compañero de sobra (>200k) pero no llega
        // a tumbar al líder.
        let tokens = 250_000
        store.ingest(event("evoluciona-a-mitad", tokens: tokens))

        let after = try unwrap(store.activeGym).battle
        expectEqual(
            after.maxHP - after.currentHP,
            Int((Double(tokens) * rateShown).rounded()),
            "el daño usa el ritmo de antes del evento"
        )
        expectEqual(store.stage, EvolutionStage.one, "y aun así el compañero evolucionó")
        expectEqual(
            store.damagePerToken(against: active.gym),
            1.0,
            accuracy: 0.001,
            "a partir de ahora sí pega con el bonus de etapa"
        )
    }

    /// La celebración es lo que convierte la medalla en un desbloqueo y no en
    /// un contador que sube: tiene que decir si el rango cambió y qué abre.
    static func testMedalCelebration() throws {
        let store = primed(wildHP: 10)
        var hp = try enterGym(store).maxHP
        store.ingest(event("gana-1", tokens: hp * 2))

        let first = try unwrap(store.lastMedal)
        expectEqual(first.gym.medal, "Medalla Roca")
        expectEqual(first.medals, 1)
        expectNil(first.newRank, "una medalla no sube de rango")
        expectTrue(first.unlocked.isEmpty)
        expectEqual(first.headline, "¡Medalla Roca!")

        // La segunda sí: Entrenador, que es lo que abre los raros.
        store.dismissMedalCelebration()
        expectNil(store.lastMedal, "se puede cerrar antes de tiempo")
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        hp = try enterGym(store, id: "abre-2").maxHP
        store.ingest(event("gana-2", tokens: hp * 3))

        let second = try unwrap(store.lastMedal)
        expectEqual(second.medals, 2)
        expectEqual(second.newRank, TrainerRank.entrenador)
        expectEqual(second.unlocked, [Rarity.rare], "el rango nuevo abre justo los raros")
        expectTrue(second.headline.contains("Entrenador"))
    }
}
