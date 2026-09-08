import AppKit
import Combine
import PokeTokenBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = GameStore()
    private let sprites = SpriteStore()
    private lazy var sources = TokenSourceCoordinator(store: store)
    private var statusItem: StatusItemController?
    private var scalingObserver: AnyCancellable?
    private var hud: HUDController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.ensureEncounter()
        statusItem = StatusItemController(store: store, sprites: sprites, sources: sources)
        hud = HUDController(store: store, sprites: sprites)
        sources.start()
        sprites.scaling = store.state.settings.spriteScaling
        sprites.scale = store.state.settings.spriteScale
        scalingObserver = store.$state
            .map { ($0.settings.spriteScaling, $0.settings.spriteScale) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] scaling, scale in
                self?.sprites.scaling = scaling
                self?.sprites.scale = scale
            }
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
            let shiny = store.state.activeCompanion?.displaysShiny ?? false
            _ = sprites.image(speciesID: form.id, shiny: shiny)
            // También el animado: su ficha se abre con un clic derecho y así no
            // aparece primero el estático y salta.
            _ = sprites.image(speciesID: form.id, shiny: shiny, animated: true)
        }
        if let encounter = store.state.encounter {
            _ = sprites.image(speciesID: encounter.speciesID, shiny: encounter.isShiny)
            _ = sprites.image(speciesID: encounter.speciesID, shiny: encounter.isShiny, animated: true)
        }
        for starter in store.pokedex.starters {
            _ = sprites.image(speciesID: starter.id, shiny: false)
        }
    }
}
