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

        // La Pokédex completa y la ficha de algo que no tienes.
        store.showingPokedex = true
        ok = layout("pokédex (\(store.pokedexCaptured)/251)") && ok
        store.selectedDexSpeciesID = 150
        ok = layout("ficha de un Mewtwo sin ver") && ok
        store.selectedDexSpeciesID = nil
        store.pokedexFilter.onlyMissing = true
        ok = layout("pokédex solo los que faltan") && ok
        store.pokedexFilter.reset()
        store.showingPokedex = false

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
        hudController = nil

        print(ok ? "  ✓ el árbol de vistas renderiza" : "  ✗ algo no cuadra")
        return ok ? 0 : 1
    }
}
