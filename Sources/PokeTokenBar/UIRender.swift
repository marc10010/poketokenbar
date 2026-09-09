import AppKit
import PokeTokenBarCore
import SwiftUI

/// `PokeTokenBar --render-ui <carpeta>` pinta las superficies a PNG sin abrir
/// ventanas ni tocar la pantalla. Existe por dos motivos: el smoke test mide
/// tamaños pero no dice **dónde** cae cada cosa, y en una máquina sin permiso
/// de captura de pantalla no hay otra forma de mirar. De aquí salen también
/// las capturas del README, así que son reproducibles: mismo estado, misma
/// semilla, mismas imágenes.
@MainActor
enum UIRender {
    private static let popoverSize = NSSize(width: 380, height: 620)
    private static let compactHUD = NSSize(width: 268, height: 104)
    private static let expandedHUD = NSSize(width: 380, height: 460)

    /// Formas base, que es lo único que aparece en libertad: capturar una forma
    /// evolucionada la dibujaría como su base hasta que ganase tokens, y la
    /// captura mentiría sobre lo que se ve jugando.
    private static let boxSpecies = [1, 4, 63, 129, 147, 152, 172, 179, 194, 209, 220, 228]

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
        store.ingest(UsageEvent(id: "render", inputTokens: 640_000, outputTokens: 160_000))
        for species in boxSpecies { store.debugCapture(speciesID: species) }
        store.debugDefeatGyms(upTo: 3)
        // La celebración dura 12 s y taparía la vista de combate: la de la
        // medalla se hace aparte, ganando un gimnasio de verdad.
        store.dismissMedalCelebration()

        var written: [String] = []

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

        func write(_ name: String, _ view: NSView) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            let url = directory.appendingPathComponent("\(name).png")
            try? data.write(to: url)
            written.append(url.lastPathComponent)
        }

        /// Los sprites bajan de la red y la vista los pide al dibujar, así que
        /// sin esperarlos las capturas saldrían con los huecos "#N".
        func warm(_ ids: [Int], seconds: TimeInterval = 12) {
            let wanted = Set(ids)
            for id in wanted { _ = sprites.image(speciesID: id, shiny: false) }
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                let missing = wanted.filter { sprites.image(speciesID: $0, shiny: false) == nil }
                if missing.isEmpty { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }

        let encounterID = store.state.encounter?.speciesID
        warm(boxSpecies + [155, 156].compactMap { $0 } + [encounterID].compactMap { $0 })

        // --- HUD
        store.updateSettings { $0.hudSize = nil }
        write("hud-plegado", hosted(HUDView(), size: compactHUD))
        store.updateSettings { $0.hudSize = HUDSize(width: expandedHUD.width, height: expandedHUD.height) }
        write("hud-desplegado", hosted(HUDView(), size: expandedHUD))

        // --- Popover
        store.updateSettings { $0.hudSize = nil }
        store.selectedTab = "combate"
        write("popover-combate", hosted(RootView(), size: popoverSize))

        store.selectedTab = "progreso"
        write("popover-progreso", hosted(RootView(), size: popoverSize))

        // El barco a Kanto: el Alto Mando ganado y la Pokédex a medias.
        store.debugDefeatGyms(upTo: 8)
        store.debugWinLeague("johto")
        store.toggleSection("Rango")
        store.toggleSection("Legendarios")
        store.toggleSection("Zonas")
        write("popover-barco", hosted(RootView(), size: popoverSize))
        store.toggleSection("Rango")
        store.toggleSection("Legendarios")
        store.toggleSection("Zonas")

        // Con una zona enfocada: es lo que hace visible el tamaño del bombo.
        if let small = store.unlockedZones.min(by: { store.focusSummary($0).pool < store.focusSummary($1).pool }) {
            store.focus(zoneID: small.id)
            store.toggleSection("Rango")
            store.toggleSection("Ligas")
            store.toggleSection("Legendarios")
            write("popover-zonas", hosted(RootView(), size: popoverSize))
            store.toggleSection("Rango")
            store.toggleSection("Ligas")
            store.toggleSection("Legendarios")
            store.focus(zoneID: nil)
        }

        // Clic en el compañero y clic en el rival, desde la pestaña de combate.
        store.selectedTab = "combate"
        store.selectedBoxGroupID = store.activeGroupID
        write("popover-combate-ficha-companero", hosted(RootView(), size: popoverSize))
        store.selectedBoxGroupID = nil
        store.inspectingRival = true
        write("popover-combate-ficha-rival", hosted(RootView(), size: popoverSize))
        store.inspectingRival = false

        // Un Eevee listo para evolucionar: es donde se ven las ramas.
        store.debugCapture(speciesID: 133, tokensEarned: 260_000)
        if let eevee = store.state.box.last {
            store.setActiveCompanion(eevee.id)
            warm([133, 134, 135, 136, 196, 197])
            store.selectedTab = "caja"
            store.selectedBoxGroupID = store.activeGroupID
            write("popover-ramas", hosted(RootView(), size: popoverSize))
            store.selectedBoxGroupID = nil
        }

        // Rival fijo de fuego para que los puntos de eficacia de la caja salgan
        // siempre iguales en la captura.
        store.debugSetEncounter(WildEncounter(speciesID: 58, isShiny: false, rarity: .common, maxHP: 900_000))
        warm([58])
        store.selectedTab = "caja"
        write("popover-caja", hosted(RootView(), size: popoverSize))

        store.selectedBoxGroupID = store.boxGroups.first { $0.id != store.activeGroupID }?.id
        write("popover-caja-ficha", hosted(RootView(), size: popoverSize))
        store.selectedBoxGroupID = nil

        store.updateSettings { $0.boxDensity = .lista }
        write("popover-caja-lista", hosted(RootView(), size: popoverSize))
        store.updateSettings { $0.boxDensity = .rejilla }

        // La Pokédex pide 251 sprites; solo hacen falta los que se ven.
        warm(Array(1...45))
        store.selectedTab = "pokedex"
        write("popover-pokedex", hosted(RootView(), size: popoverSize))
        store.selectedTab = "combate"

        // --- Gimnasio: abrirlo de verdad, no simularlo
        store.debugSetGymCounters(tokens: GameRules.gymTokenInterval, captures: 0)
        store.debugSetEncounter(WildEncounter(speciesID: 19, isShiny: false, rarity: .common, maxHP: 10))
        store.ingest(UsageEvent(id: "render-gym", inputTokens: 10, outputTokens: 0))
        if let waiting = store.availableGym {
            warm([waiting.signatureSpeciesID])
            store.selectedTab = "combate"
            write("popover-gimnasio-disponible", hosted(RootView(), size: popoverSize))
            store.startGym(waiting.id)
        }
        if let gym = store.activeGym {
            warm([gym.gym.signatureSpeciesID])
            write("hud-gimnasio", hosted(HUDView(), size: compactHUD))
            store.selectedTab = "combate"
            write("popover-gimnasio", hosted(RootView(), size: popoverSize))
            // Y ganarlo, para la celebración de medalla.
            store.ingest(UsageEvent(id: "render-medalla", inputTokens: gym.battle.maxHP * 6, outputTokens: 0))
            if store.lastMedal != nil {
                write("hud-medalla", hosted(HUDView(), size: NSSize(width: 300, height: 120)))
                write("popover-medalla", hosted(RootView(), size: popoverSize))
            }
        }

        for name in written.sorted() { print(name) }
        return written.isEmpty ? 1 : 0
    }
}
