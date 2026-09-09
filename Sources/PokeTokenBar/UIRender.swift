import AppKit
import PokeTokenBarCore
import SwiftUI

/// `PokeTokenBar --render-ui <carpeta>` pinta las superficies a PNG sin abrir
/// ventanas ni tocar la pantalla. Existe porque el smoke test mide tamaños
/// pero no dice **dónde** cae cada cosa, y en esta máquina no hay permiso de
/// captura de pantalla: sin esto, revisar una posición es preguntar.
@MainActor
enum UIRender {
    static func run(into directory: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("poketokenbar-render/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let store = GameStore(
            file: StateFileStore(url: sandbox.appendingPathComponent("state.json")),
            rng: SeededRandomProvider(seed: 5)
        )
        let sprites = SpriteStore()
        store.chooseStarter(speciesID: 155)
        store.ingest(UsageEvent(id: "render", inputTokens: 4_000, outputTokens: 1_000))
        // Solo formas base, que es lo único que aparece en libertad: capturar
        // una forma evolucionada la dibujaría como su base hasta que ganase
        // tokens, y la imagen mentiría sobre lo que se ve jugando.
        for species in [1, 4, 63, 129, 147, 152, 172, 179, 194] {
            store.debugCapture(speciesID: species)
        }

        // Los sprites bajan de la red: sin esperarlos saldrían los huecos.
        for id in [155, store.state.encounter?.speciesID].compactMap({ $0 }) {
            _ = sprites.image(speciesID: id, shiny: false)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))

        func hosted<V: View>(_ view: V, size: NSSize) -> NSView {
            let host = NSHostingView(
                rootView: view
                    .environmentObject(store)
                    .environmentObject(sprites)
                    .frame(width: size.width, height: size.height)
            )
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            return host
        }

        var written: [String] = []
        func write(_ name: String, _ view: NSView) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            let url = directory.appendingPathComponent("\(name).png")
            try? data.write(to: url)
            written.append(url.path)
        }

        store.updateSettings { $0.hudSize = nil }
        write("hud-plegado", hosted(HUDView(), size: NSSize(width: 268, height: 104)))

        store.updateSettings { $0.hudSize = HUDSize(width: 380, height: 460) }
        write("hud-desplegado", hosted(HUDView(), size: NSSize(width: 380, height: 460)))

        // Un gimnasio abierto: es el panel que hasta ahora no tenía botón.
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(UsageEvent(id: "render-gym", inputTokens: 10, outputTokens: 0))
        if store.activeGym != nil {
            store.updateSettings { $0.hudSize = nil }
            write("hud-gimnasio-plegado", hosted(HUDView(), size: NSSize(width: 268, height: 104)))
        }

        store.selectedTab = "caja"
        write("popover-caja", hosted(RootView(), size: NSSize(width: 380, height: 620)))

        for path in written { print(path) }
        return written.isEmpty ? 1 : 0
    }
}
