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
        print(ok ? "  ✓ el árbol de vistas renderiza" : "  ✗ alguna vista mide 0")
        return ok ? 0 : 1
    }
}
