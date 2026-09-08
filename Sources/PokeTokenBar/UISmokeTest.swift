import AppKit
import PokeTokenBarCore
import SwiftUI

/// `PokeTokenBar --ui-smoke-test` monta el árbol de SwiftUI en un estado
/// desechable y fuerza el layout de las dos ramas (sin inicial y en combate).
/// Sirve de humo en CI, donde no hay nadie para abrir el popover.
@MainActor
enum UISmokeTest {
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

        store.updateSettings {
            $0.hudFreeOrigin = nil
            $0.hudLocked = false
        }
        hudController = nil

        print(ok ? "  ✓ el árbol de vistas renderiza" : "  ✗ algo no cuadra")
        return ok ? 0 : 1
    }
}
