import Foundation
import PokeTokenBarCore

@MainActor
enum GymBattleTests: TestSuite {
    static let suiteName = "Gimnasios · combate"

    static let tests: [(String, () throws -> Void)] = [
        ("el gimnasio se abre al capturar, no a mitad", testGymOpensOnCaptureOnly),
        ("los tokens sobrantes de la captura entran al líder", testLeftoverTokensHitTheLeader),
        ("derrotarlo da medalla y no captura", testDefeatGivesMedalNotCapture),
        ("la medalla se da una sola vez", testMedalIsAwardedOnce),
        ("con el cruce bloqueado el HP no se mueve", testBlockedGymDoesNotBudge),
        ("cambiar de compañero desbloquea el combate", testSwitchingCompanionUnblocks),
        ("los contadores se reinician al terminar", testCountersResetOnGymEnd),
        ("las medallas abren los tiers", testMedalsUnlockTiers),
        ("los tokens del gimnasio cuentan para el ledger y la evolución", testGymTokensStillCount),
        ("la medalla se celebra y dice qué desbloquea", testMedalCelebration),
        ("el ritmo es el que muestra la UI, sin evolucionar a mitad", testRateDoesNotChangeMidEvent),
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

    static func testGymOpensOnCaptureOnly() throws {
        let store = primed(wildHP: 10_000)
        expectNil(store.activeGym, "todavía no")

        // Un evento que no remata al salvaje no abre nada, aunque el contador
        // esté pasado de sobra.
        store.ingest(event("roza", tokens: 9_999))
        expectNil(store.activeGym, "el gimnasio no interrumpe un combate")
        expectEqual(store.state.encounter?.currentHP, 1)

        store.ingest(event("remata", tokens: 1))
        let active = try unwrap(store.activeGym)
        expectEqual(active.gym.id, "johto-violet", "el primero del orden")
        expectNil(store.state.encounter, "no hay salvaje mientras hay líder")
        expectTrue(active.gym.hpRange.contains(active.battle.maxHP))
    }

    static func testLeftoverTokensHitTheLeader() throws {
        // Squirtle contra Pidgeotto es neutro; absorción 0,25 y etapa base
        // dejan 0,75 HP por token.
        let store = primed(wildHP: 10_000)
        store.updateSettings { $0.typeEffectivenessEnabled = true }
        store.ingest(event("mata-y-sigue", tokens: 110_000))

        let active = try unwrap(store.activeGym)
        let spent = 110_000 - 10_000
        expectEqual(active.battle.tokensSpent, spent, "los 100k que sobran van al líder")
        expectEqual(
            active.battle.maxHP - active.battle.currentHP,
            Int((Double(spent) * 0.75).rounded()),
            "a 0,75 HP por token"
        )
    }

    static func testDefeatGivesMedalNotCapture() throws {
        let store = primed(wildHP: 10)
        store.ingest(event("abre", tokens: 10))
        let active = try unwrap(store.activeGym)
        let boxBefore = store.state.box.count

        // De sobra para tumbarlo: sin efectividad de tipos, 1 HP por token
        // menos la absorción de 0,25 -> 0,75.
        store.ingest(event("gana", tokens: active.battle.currentHP * 2))

        expectNil(store.activeGym, "el gimnasio se cierra")
        expectEqual(store.medals, 1)
        expectEqual(store.rank, TrainerRank.novato, "una medalla todavía no sube de rango")
        expectEqual(store.state.gyms.defeated, ["johto-violet"])
        expectEqual(store.lastMedal?.gym.medal, "Medalla Céfiro")
        expectNotNil(store.state.encounter, "vuelve a haber salvaje")
        expectTrue(
            store.state.box.count >= boxBefore,
            "el líder no se captura: la caja solo puede crecer por los salvajes del sobrante"
        )
        expectFalse(
            store.state.box.contains { $0.speciesID == 17 },
            "Pidgeotto, el Pokémon del líder, no acaba en la caja"
        )
    }

    /// Un evento monstruoso puede encadenar gimnasios: tras cerrar el primero,
    /// el sobrante captura salvajes y esas capturas vuelven a cumplir el
    /// disparador. Lo que no puede pasar es dar dos veces la misma medalla.
    static func testMedalIsAwardedOnce() throws {
        let store = primed(wildHP: 10)
        store.ingest(event("abre", tokens: 10))
        let hp = try unwrap(store.activeGym).battle.maxHP
        store.ingest(event("bestial", tokens: hp * 20))

        expectGreaterThan(store.medals, 0)
        expectEqual(
            Set(store.state.gyms.defeated).count,
            store.state.gyms.defeated.count,
            "ninguna medalla repetida aunque el evento pase de sobra del HP"
        )
        expectEqual(store.state.gyms.defeated.first, "johto-violet", "y en orden")

        // El invariante, directo: otorgar dos veces el mismo gimnasio no suma.
        var progress = GymProgress()
        progress.award(gymID: "johto-violet")
        progress.award(gymID: "johto-violet")
        expectEqual(progress.medals, 1)
    }

    /// Con el cruce bloqueado el HP no se mueve por muchos tokens que entren, y
    /// los tokens se gastan igual: es un bloqueo, no un ahorro.
    static func testBlockedGymDoesNotBudge() throws {
        let store = makeStore(seed: 9)
        store.chooseStarter(speciesID: 7)
        store.debugDefeatGyms(upTo: 15)
        let giovanni = try unwrap(store.debugOpenNextGym())
        expectEqual(giovanni.leader, "Giovanni")

        // Pikachu (eléctrico) contra Rhydon (tierra/roca): eléctrico no toca a
        // tierra, así que el cruce cae al suelo de ×0,25 y con absorción 1,5 el
        // progreso es cero.
        store.debugCapture(speciesID: 25)
        store.setActiveCompanion(try unwrap(store.state.box.last).id)
        expectTrue(store.isBlocked(against: giovanni))

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
        store.debugDefeatGyms(upTo: 15)                   // siguiente: Giovanni, absorción 1,5
        let giovanni = try unwrap(store.nextGym)

        // Rhydon es tierra/roca. Squirtle (agua) le hace ×4: 4 - 1,5 = 2,5.
        expectFalse(store.isBlocked(against: giovanni))
        expectEqual(store.gymDamagePerToken(for: giovanni), 2.5, accuracy: 0.001)

        // Con un compañero de tipo eléctrico, tierra es inmune: cae al suelo de
        // ×0,25 y contra absorción 1,5 el progreso es cero.
        store.debugCapture(speciesID: 25)                 // Pikachu
        let pikachu = try unwrap(store.state.box.last)
        store.setActiveCompanion(pikachu.id)
        expectTrue(store.isBlocked(against: giovanni), "eléctrico no le hace nada a tierra")
        expectEqual(store.gymDamagePerToken(for: giovanni), 0, accuracy: 0.001)

        // Volver al Squirtle desbloquea sin tocar el daño ya hecho.
        let squirtle = try unwrap(store.state.box.first)
        store.setActiveCompanion(squirtle.id)
        expectFalse(store.isBlocked(against: giovanni))
    }

    static func testCountersResetOnGymEnd() throws {
        let store = primed(wildHP: 10)
        store.ingest(event("abre", tokens: 10))
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
        expectTrue(SpawnService().availableTiers(rank: store.rank).contains(.legendary))
    }

    static func testGymTokensStillCount() throws {
        let store = primed(wildHP: 10)
        store.ingest(event("abre", tokens: 10))
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
        store.ingest(event("abre", tokens: 10))
        let active = try unwrap(store.activeGym)
        let rateShown = store.gymDamagePerToken(for: active.gym)
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
            store.gymDamagePerToken(for: active.gym),
            1.0,
            accuracy: 0.001,
            "a partir de ahora sí pega con el bonus de etapa"
        )
    }

    /// La celebración es lo que convierte la medalla en un desbloqueo y no en
    /// un contador que sube: tiene que decir si el rango cambió y qué abre.
    static func testMedalCelebration() throws {
        let store = primed(wildHP: 10)
        store.ingest(event("abre", tokens: 10))
        var hp = try unwrap(store.activeGym).battle.maxHP
        store.ingest(event("gana-1", tokens: hp * 2))

        let first = try unwrap(store.lastMedal)
        expectEqual(first.gym.medal, "Medalla Céfiro")
        expectEqual(first.medals, 1)
        expectNil(first.newRank, "una medalla no sube de rango")
        expectTrue(first.unlocked.isEmpty)
        expectEqual(first.headline, "¡Medalla Céfiro!")

        // La segunda sí: Entrenador, que es lo que abre los raros.
        store.dismissMedalCelebration()
        expectNil(store.lastMedal, "se puede cerrar antes de tiempo")
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(event("abre-2", tokens: 10))
        hp = try unwrap(store.activeGym).battle.maxHP
        store.ingest(event("gana-2", tokens: hp * 3))

        let second = try unwrap(store.lastMedal)
        expectEqual(second.medals, 2)
        expectEqual(second.newRank, TrainerRank.entrenador)
        expectEqual(second.unlocked, [Rarity.rare], "el rango nuevo abre justo los raros")
        expectTrue(second.headline.contains("Entrenador"))
    }
}
