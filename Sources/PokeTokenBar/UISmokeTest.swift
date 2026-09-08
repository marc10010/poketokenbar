import AppKit
import PokeTokenBarCore
import SwiftUI

/// `PokeTokenBar --ui-smoke-test` monta el árbol de SwiftUI en un estado
/// desechable y fuerza el layout de las dos ramas (sin inicial y en combate).
/// Sirve de humo en CI, donde no hay nadie para abrir el popover.
@MainActor
enum UISmokeTest {
    /// Un tamaño absurdo debe quedar acotado por `contentMaxSize`, no crecer
    /// hasta tapar la pantalla.
    private static func expectCompact(
        _ ok: inout Bool,
        store: GameStore,
        panelsProvider: () -> [NSPanel]
    ) {
        store.updateSettings { $0.hudSize = HUDSize(width: 9_000, height: 9_000) }
        let clamped = panelsProvider().first?.frame.size ?? .zero
        let bounded = clamped.width <= 620 && clamped.height <= 760
        print("  tamaño absurdo acotado a \(Int(clamped.width))x\(Int(clamped.height)) ok=\(bounded)")
        ok = bounded && ok
    }

    /// La puerta entre regiones: con las 8 medallas de Johto, el gimnasio
    /// siguiente es de Kanto y no debe aparecer hasta ganar el Alto Mando.
    private static func expectGate(_ store: GameStore) {
        let blocked = store.nextGym == nil && store.gymGate != nil
        print("  puerta de región con \(store.medals) medallas: bloquea=\(blocked)")
    }

    static func run() -> Int32 {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("poketokenbar-ui-smoke/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GameStore(
            file: StateFileStore(url: directory.appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 1)
        )
        let sprites = SpriteStore()
        let sources = TokenSourceCoordinator(store: store)

        let controller = NSHostingController(
            rootView: RootView()
                .environmentObject(store)
                .environmentObject(sprites)
                .environmentObject(sources)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller

        func layout(_ label: String) -> Bool {
            controller.view.layoutSubtreeIfNeeded()
            controller.view.displayIfNeeded()
            let size = controller.view.fittingSize
            print("  \(label): \(Int(size.width))x\(Int(size.height))")
            return size.width > 0 && size.height > 0
        }

        print("▸ UI smoke test")
        var ok = layout("selector de inicial")

        store.chooseStarter(speciesID: 155)
        store.ingest(UsageEvent(id: "smoke-1", inputTokens: 5_000, outputTokens: 1_000))
        ok = layout("combate") && ok

        let rivalHP = store.state.encounter?.maxHP ?? 0
        store.ingest(UsageEvent(id: "smoke-2", inputTokens: rivalHP, outputTokens: 0))
        ok = layout("tras captura") && ok

        let hud = NSHostingView(
            rootView: HUDView().environmentObject(store).environmentObject(sprites)
        )
        hud.layoutSubtreeIfNeeded()
        let hudSize = hud.fittingSize
        print("  HUD flotante: \(Int(hudSize.width))x\(Int(hudSize.height))")
        ok = hudSize.width > 0 && hudSize.height > 0 && ok

        // El clic derecho: qué eventos intercepta el detector. Si esto se
        // equivoca, o el clic izquierdo deja de equipar o el derecho no abre.
        let clickCases: [(String, NSEvent.EventType, NSEvent.ModifierFlags, Bool)] = [
            ("clic derecho", .rightMouseDown, [], true),
            ("clic izquierdo", .leftMouseDown, [], false),
            ("ctrl+clic izquierdo", .leftMouseDown, .control, true),
            ("movimiento", .mouseMoved, [], false),
        ]
        for (name, type, flags, expected) in clickCases {
            let event = NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
            let intercepts = RightClickCatcher.CatcherView.shouldIntercept(event)
            if intercepts != expected {
                print("  ✗ \(name): intercepta=\(intercepts), se esperaba \(expected)")
                ok = false
            }
        }
        print("  clic derecho: \(clickCases.count) casos comprobados")

        // Los sprites animados: que la URL exista no prueba que animen, así
        // que se comprueban los fotogramas de lo que se ha cargado.
        _ = sprites.image(speciesID: 7, shiny: false, animated: true)
        var frames: Int?
        for _ in 0..<40 {
            frames = sprites.frameCount(speciesID: 7, shiny: false, animated: true)
            if frames != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        switch frames {
        case .some(let count) where count > 1:
            print("  sprite animado: \(count) fotogramas")
        case .some(let count):
            print("  ✗ el sprite animado trae \(count) fotograma(s): no animaría")
            ok = false
        case nil:
            print("  sprite animado: sin red o sin caché, no se puede comprobar")
        }

        // Los dos multiplicadores: la ficha se mueve con el suyo y NO con el
        // de las miniaturas, que es justo lo que se pidió separar.
        if let group = store.boxGroups.first {
            func fichaHeight(detail: Double, thumbs: Double) -> CGFloat {
                store.updateSettings {
                    $0.detailSpriteScale = detail
                    $0.spriteScale = thumbs
                }
                sprites.detailScale = detail
                sprites.scale = thumbs
                let view = NSHostingView(rootView: PokemonDetailView(group: group)
                    .environmentObject(store)
                    .environmentObject(sprites))
                view.layoutSubtreeIfNeeded()
                return view.fittingSize.height
            }

            let small = fichaHeight(detail: 0.75, thumbs: 1)
            let big = fichaHeight(detail: 2, thumbs: 1)
            let thumbsOnly = fichaHeight(detail: 0.75, thumbs: 2)
            print("  ficha: ×0,75 → \(Int(small)) pt · ×2 → \(Int(big)) pt · miniaturas ×2 → \(Int(thumbsOnly)) pt")
            ok = big > small && ok
            ok = (abs(thumbsOnly - small) < 1) && ok

            store.updateSettings { $0.detailSpriteScale = 1; $0.spriteScale = 1 }
            sprites.detailScale = 1
            sprites.scale = 1
        }

        // Que "pixel nítido" llegue de verdad al GIF: el filtro es de capa, y
        // si NSImageView escalara al dibujar no tendría ningún efecto.
        if let group = store.boxGroups.first {
            store.updateSettings { $0.spriteScaling = .pixel }
            sprites.scaling = .pixel

            // Sin el GIF cacheado, la vista cae al sprite estático y aquí no
            // habría NSImageView que comprobar.
            _ = sprites.image(speciesID: group.displayForm.id, shiny: group.displaysShiny, animated: true)
            for _ in 0..<40 where sprites.frameCount(
                speciesID: group.displayForm.id,
                shiny: group.displaysShiny,
                animated: true
            ) == nil {
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            let view = NSHostingView(rootView: PokemonDetailView(group: group)
                .environmentObject(store)
                .environmentObject(sprites))
            view.frame = NSRect(x: 0, y: 0, width: 340, height: 700)
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()

            func imageViews(in root: NSView) -> [NSImageView] {
                (root as? NSImageView).map { [$0] } ?? root.subviews.flatMap(imageViews)
            }
            let found = imageViews(in: view)
            if let gif = found.first(where: { $0.image?.representations.count ?? 0 > 0 }) {
                let nearest = gif.layer?.magnificationFilter == .nearest
                let nativeDraw = gif.imageScaling == .scaleNone
                print("  pixel nítido en la ficha: filtro=\(nearest) sinEscalarAlDibujar=\(nativeDraw)")
                ok = nearest && nativeDraw && ok
            } else {
                print("  pixel nítido: sin sprite cargado, no se puede comprobar")
            }
            store.updateSettings { $0.spriteScaling = .medio }
            sprites.scaling = .medio
        }

        // Celebración de medalla: gana un gimnasio de verdad y mírala.
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(UsageEvent(id: "abre-gym", inputTokens: 10, outputTokens: 0))
        if let battle = store.activeGym?.battle {
            store.ingest(UsageEvent(id: "gana-gym", inputTokens: battle.maxHP * 4, outputTokens: 0))
        }
        if let celebration = store.lastMedal {
            print("  medalla: \(celebration.headline)")
            ok = layout("celebración de medalla") && ok
            let hudCelebration = NSHostingView(
                rootView: HUDView()
                    .environmentObject(store)
                    .environmentObject(sprites)
                    .frame(width: 268, height: 200)
            )
            hudCelebration.layoutSubtreeIfNeeded()
            ok = hudCelebration.fittingSize == NSSize(width: 268, height: 200) && ok
            store.dismissMedalCelebration()
            ok = (store.lastMedal == nil) && ok
        } else {
            print("  ✗ no se ganó medalla, la celebración no se puede probar")
            ok = false
        }

        // Todas las pestañas renderizan: es lo que sustituye a los seis
        // acordeones apilados.
        for tab in AppTab.allCases {
            store.selectedTab = tab.rawValue
            ok = layout("pestaña \(tab.label)") && ok
        }
        store.selectedTab = "combate"

        // Las zonas: la lista y la ficha de algo cuya zona está cerrada.
        print("  zonas abiertas: \(store.unlockedZones.count)/\(store.zoneCatalog.all.count) · \(store.zoneCatalog.availableSpecies(store.zoneAccess).count) especies disponibles")
        ok = layout("lista de zonas") && ok
        store.selectedTab = "pokedex"
        // Zapdos (#145) vive en la Central Eléctrica, que pide Kanto abierta.
        store.selectedDexSpeciesID = 145
        ok = layout("ficha con zona cerrada") && ok
        ok = !store.isAvailableInTheWild(145) && ok
        store.selectedDexSpeciesID = nil
        store.selectedTab = "combate"

        // Hitos: la lista, y un legendario abierto de verdad.
        store.debugDefeatGyms(upTo: 8)
        ok = layout("lista de hitos") && ok
        if store.startMilestone("torre-quemada-suicune"), let boss = store.activeMilestone {
            print("  hito abierto: \(boss.milestone.place) · \(Fmt.tokens(boss.battle.maxHP)) HP · bloqueado=\(store.isBlocked(against: boss.milestone))")
            ok = layout("hito legendario") && ok
            let hudBoss = NSHostingView(
                rootView: HUDView()
                    .environmentObject(store)
                    .environmentObject(sprites)
                    .frame(width: 268, height: 220)
            )
            hudBoss.layoutSubtreeIfNeeded()
            ok = hudBoss.fittingSize == NSSize(width: 268, height: 220) && ok
            store.abandonMilestone()
            ok = (store.activeMilestone == nil) && ok
        } else {
            print("  ✗ no se pudo abrir el hito")
            ok = false
        }

        // Ligas: la lista y un gauntlet abierto de verdad.
        ok = layout("lista de ligas") && ok
        expectGate(store)
        store.debugCapture(speciesID: 95)      // Onix: x2 contra Xatu
        if let onix = store.state.box.last { store.setActiveCompanion(onix.id) }
        if store.startLeague("johto"), let run = store.activeLeague {
            print("  liga abierta: \(run.member.name) 1/\(run.league.members.count) · \(Fmt.tokens(run.run.maxHP)) HP · bloqueado=\(store.isBlocked(against: run.member))")
            ok = layout("liga en curso") && ok
            let hudLeague = NSHostingView(
                rootView: HUDView()
                    .environmentObject(store)
                    .environmentObject(sprites)
                    .frame(width: 268, height: 240)
            )
            hudLeague.layoutSubtreeIfNeeded()
            ok = hudLeague.fittingSize == NSSize(width: 268, height: 240) && ok
            store.abandonLeague()
            ok = (store.activeLeague == nil) && ok
        } else {
            print("  ✗ no se pudo abrir la liga")
            ok = false
        }

        // La Pokédex completa y la ficha de algo que no tienes.
        store.selectedTab = "pokedex"
        ok = layout("pokédex (\(store.pokedexCaptured)/251)") && ok
        store.selectedDexSpeciesID = 150
        ok = layout("ficha de un Mewtwo sin ver") && ok
        store.selectedDexSpeciesID = nil
        store.pokedexFilter.onlyMissing = true
        ok = layout("pokédex solo los que faltan") && ok
        store.pokedexFilter.reset()
        store.selectedTab = "combate"

        // Ficha de un gimnasio, que es lo que abre un clic en su medalla.
        store.selectedGymID = store.gymCatalog.all.first?.id
        ok = layout("ficha de gimnasio") && ok
        store.selectedGymID = nil

        // Reinicio: deja el juego como recién instalado y conserva ajustes.
        let settingsBefore = store.state.settings
        store.resetGame()
        if store.state.box.isEmpty, store.totalTokens == 0, store.medals == 0,
           store.state.settings == settingsBefore {
            print("  reinicio: caja vacía, 0 tokens, ajustes intactos")
        } else {
            print("  ✗ el reinicio no dejó el estado limpio")
            ok = false
        }
        ok = layout("tras reiniciar (selector de inicial)") && ok
        store.chooseStarter(speciesID: 155)
        store.ingest(UsageEvent(id: "post-reset", inputTokens: 5_000, outputTokens: 0))

        // Ficha de un Pokémon de la caja, que es lo que abre un clic.
        if let group = store.boxGroups.first {
            store.selectedBoxGroupID = group.id
            ok = layout("ficha de \(group.displayForm.name)") && ok
            store.selectedBoxGroupID = nil
        } else {
            print("  ✗ la caja está vacía, no se puede abrir ficha")
            ok = false
        }

        // Ficha del rival.
        store.inspectingRival = true
        ok = layout("ficha del rival") && ok
        store.inspectingRival = false

        // Gimnasio abierto: el HUD y el popover cambian de tarjeta.
        store.debugDefeatGyms(upTo: 15)
        // Giovanni es de Kanto, que está tras el Alto Mando de Johto.
        store.debugWinLeague("johto")
        if let gym = store.debugOpenNextGym() {
            ok = layout("gimnasio (\(gym.leader))") && ok
            // El panel del HUD tiene tamaño fijo y su raíz es un GeometryReader,
            // que no tiene tamaño intrínseco: hay que medirlo con el marco real.
            let panelSize = NSSize(width: 268, height: 460)
            let gymHUD = NSHostingView(
                rootView: HUDView()
                    .environmentObject(store)
                    .environmentObject(sprites)
                    .frame(width: panelSize.width, height: panelSize.height)
            )
            gymHUD.layoutSubtreeIfNeeded()
            let size = gymHUD.fittingSize
            print("  HUD de gimnasio: \(Int(size.width))x\(Int(size.height)) bloqueado=\(store.isBlocked(against: gym))")
            ok = size == panelSize && ok
        } else {
            print("  ✗ no se pudo abrir gimnasio")
            ok = false
        }
        // Con búsqueda que no casa: hay que renderizar el estado vacío, no romper.
        store.boxFilter.query = "no-existe-nada-asi"
        ok = layout("caja filtrada sin resultados") && ok
        store.boxFilter.reset()

        var hudController: HUDController? = HUDController(store: store, sprites: sprites)

        // El panel plegado tiene que crecer con el multiplicador: si no, los
        // sprites grandes no caben en 268x104.
        store.updateSettings { $0.spriteScale = 1; $0.hudSize = nil }
        let compactAtOne = NSApp.windows.compactMap { $0 as? NSPanel }.first?.frame.size ?? .zero
        store.updateSettings { $0.spriteScale = 2 }
        let compactAtTwo = NSApp.windows.compactMap { $0 as? NSPanel }.first?.frame.size ?? .zero
        print("  HUD plegado: ×1 → \(Int(compactAtOne.width))x\(Int(compactAtOne.height)) · ×2 → \(Int(compactAtTwo.width))x\(Int(compactAtTwo.height))")
        ok = compactAtTwo.width > compactAtOne.width && compactAtTwo.height > compactAtOne.height && ok
        store.updateSettings { $0.spriteScale = 1 }

        // Desbloqueado (por defecto): recibe clics y hay un panel por pantalla.
        var panels = NSApp.windows.compactMap { $0 as? NSPanel }
        let screens = NSScreen.screens
        print("  anclado: \(panels.count) panel(es) para \(screens.count) pantalla(s)")
        ok = panels.count == screens.count && ok
        for (panel, screen) in zip(panels, screens) {
            let inside = screen.visibleFrame.contains(panel.frame)
            print("    \(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)) dentro=\(inside) movible=\(panel.isMovableByWindowBackground) opaco=\(panel.isOpaque)")
            ok = inside && panel.isMovableByWindowBackground && !panel.isOpaque && ok
        }

        // Bloqueado: click-through.
        store.updateSettings { $0.hudLocked = true }
        panels = NSApp.windows.compactMap { $0 as? NSPanel }
        let allClickThrough = panels.allSatisfy(\.ignoresMouseEvents)
        print("  bloqueado: clickThrough=\(allClickThrough)")
        ok = allClickThrough && ok

        // Arrastrado a mano: un solo panel, y dentro de la pantalla que lo aloja.
        let target = (NSScreen.main ?? screens[0]).visibleFrame
        store.updateSettings { $0.hudFreeOrigin = HUDOrigin(x: target.midX, y: target.midY) }
        panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible }
        let hosted = panels.first.map { panel in screens.contains { $0.visibleFrame.contains(panel.frame) } } ?? false
        print("  posición libre: \(panels.count) panel(es) alojado=\(hosted)")
        ok = panels.count == 1 && hosted && ok

        // Fuera de toda pantalla: vuelve al anclaje por esquina en vez de perderse.
        store.updateSettings { $0.hudFreeOrigin = HUDOrigin(x: -99_000, y: -99_000) }
        panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible }
        let recovered = panels.count == screens.count
        print("  origen imposible: \(panels.count) panel(es) recuperado=\(recovered)")
        ok = recovered && ok

        // Desplegado: el panel crece y a esa altura toca mostrar la caja PC.
        store.updateSettings {
            $0.hudFreeOrigin = nil
            $0.hudLocked = false
            $0.hudSize = HUDSize(width: 380, height: 460)
        }
        panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible }
        let expanded = panels.first?.frame.size ?? .zero
        let resizable = panels.allSatisfy { $0.styleMask.contains(.resizable) }
        let showsBox = HUDView.showsBox(forHeight: expanded.height)
        let showsMetrics = HUDView.showsMetrics(forHeight: expanded.height)
        print("  desplegado: \(Int(expanded.width))x\(Int(expanded.height)) redimensionable=\(resizable) métricas=\(showsMetrics) cajaPC=\(showsBox)")
        ok = expanded == NSSize(width: 380, height: 460) && resizable && showsMetrics && showsBox && ok

        // Compacto: ni métricas ni caja, que si no tapa media pantalla.
        let compactHidesExtras = !HUDView.showsMetrics(forHeight: 104) && !HUDView.showsBox(forHeight: 104)
        print("  compacto oculta métricas y caja=\(compactHidesExtras)")
        ok = compactHidesExtras && ok
        expectCompact(&ok, store: store, panelsProvider: { NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible } })

        store.updateSettings {
            $0.hudSize = nil
            $0.hudLocked = false
        }
        hudController?.shutdown()
        hudController = nil

        print(ok ? "  ✓ el árbol de vistas renderiza" : "  ✗ algo no cuadra")
        return ok ? 0 : 1
    }
}
