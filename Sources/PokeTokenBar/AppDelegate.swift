import AppKit
import PokeTokenBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = GameStore()
    private let sprites = SpriteStore()
    private lazy var sources = TokenSourceCoordinator(store: store)
    private var statusItem: StatusItemController?
    private var hud: HUDController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.ensureEncounter()
        statusItem = StatusItemController(store: store, sprites: sprites, sources: sources)
        hud = HUDController(store: store, sprites: sprites)
        sources.start()
        prefetchSprites()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sources.stop()
        store.flush()
    }

    /// Los sprites del combate actual y de los iniciales, para que la barra no
    /// arranque con placeholders.
    private func prefetchSprites() {
        if let form = store.activeForm {
            _ = sprites.image(speciesID: form.id, shiny: store.state.activeCompanion?.isShiny ?? false)
        }
        if let encounter = store.state.encounter {
            _ = sprites.image(speciesID: encounter.speciesID, shiny: encounter.isShiny)
        }
        for starter in store.pokedex.starters {
            _ = sprites.image(speciesID: starter.id, shiny: false)
        }
    }
}
