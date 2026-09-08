import AppKit
import Combine
import PokeTokenBarCore
import SwiftUI

/// Dueño del `NSStatusItem`: compone "sprite propio vs sprite rival | HP" y
/// abre el popover con la UI de SwiftUI.
@MainActor
final class StatusItemController {
    private let store: GameStore
    private let sprites: SpriteStore
    private let sources: TokenSourceCoordinator
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var captureFlashUntil: Date?

    private static let spriteSide: CGFloat = 18

    init(store: GameStore, sprites: SpriteStore, sources: TokenSourceCoordinator) {
        self.store = store
        self.sprites = sprites
        self.sources = sources
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: RootView()
                .environmentObject(store)
                .environmentObject(sprites)
                .environmentObject(sources)
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        // Cualquier cambio de estado o sprite recién bajado redibuja la barra.
        store.$state.sink { [weak self] _ in self?.scheduleRender() }.store(in: &cancellables)
        sprites.$images.sink { [weak self] _ in self?.scheduleRender() }.store(in: &cancellables)
        store.$lastCapture
            .compactMap { $0 }
            .sink { [weak self] _ in self?.flashCapture() }
            .store(in: &cancellables)

        render()
        logGeometry(after: 0.2)
        logGeometry(after: 2.5)
    }

    /// El ítem puede existir y no verse (barra llena, pantalla con notch, otro
    /// display activo). Volcamos su geometría real para poder diagnosticarlo.
    private func logGeometry(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let button = self.statusItem.button
            let frame = button?.window?.frame ?? .zero
            let screens = NSScreen.screens
                .map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.minX))" }
                .joined(separator: ", ")
            let parts = [
                "statusItem visible=\(self.statusItem.isVisible)",
                "length=\(Int(self.statusItem.length))",
                "buttonWindow=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))",
                "title=\"\(button?.title ?? "-")\"",
                "hasImage=\(button?.image != nil)",
                "screens=[\(screens)]",
                "pid=\(ProcessInfo.processInfo.processIdentifier)",
            ]
            Diagnostics.append(parts.joined(separator: " "))
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func flashCapture() {
        captureFlashUntil = Date().addingTimeInterval(6)
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) { [weak self] in self?.render() }
    }

    /// Coalescing: una ráfaga de eventos redibuja una sola vez por ciclo de run loop.
    private var renderScheduled = false
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.renderScheduled = false
            self?.render()
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }

        guard store.state.hasStarter else {
            // Un título largo es lo primero que macOS oculta cuando la barra
            // está llena (peor aún en pantallas con notch): icono y nada más.
            button.image = NSImage(
                systemSymbolName: "circle.circle",
                accessibilityDescription: "PokeTokenBar: elige tu inicial"
            )
            button.title = ""
            return
        }

        let playerForm = store.activeForm
        let playerShiny = store.state.activeCompanion?.isShiny ?? false
        let encounter = store.state.encounter

        let playerImage = playerForm.flatMap { sprites.image(speciesID: $0.id, shiny: playerShiny) }
        let rivalImage = encounter.flatMap { sprites.image(speciesID: $0.speciesID, shiny: $0.isShiny) }
        button.image = Self.composite(player: playerImage, rival: rivalImage)

        if let flashUntil = captureFlashUntil, flashUntil > Date(),
           let speciesID = store.state.lastCaptureSpeciesID,
           let species = store.pokedex[speciesID] {
            button.title = " ¡\(species.localizedName) capturado!"
        } else if let encounter {
            button.title = " \(Fmt.compact(encounter.currentHP))/\(Fmt.compact(encounter.maxHP))"
        } else {
            button.title = " —"
        }
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        var lines: [String] = []
        if let form = store.activeForm { lines.append("Compañero: \(form.localizedName) (\(store.stage.label))") }
        if let encounter = store.state.encounter, let rival = store.pokedex[encounter.speciesID] {
            lines.append("Rival: \(rival.localizedName) [\(encounter.rarity.label)] \(Fmt.tokens(encounter.currentHP))/\(Fmt.tokens(encounter.maxHP)) HP")
        }
        lines.append("Tokens totales: \(Fmt.tokens(store.totalTokens)) · mes: \(Fmt.tokens(store.monthTokens))")
        return lines.joined(separator: "\n")
    }

    /// Dibuja los dos sprites lado a lado, el rival mirando al jugador.
    private static func composite(player: NSImage?, rival: NSImage?) -> NSImage {
        let side = spriteSide
        let gap: CGFloat = 3
        let size = NSSize(width: side * 2 + gap, height: side)

        let image = NSImage(size: size, flipped: false) { _ in
            player?.draw(
                in: NSRect(x: 0, y: 0, width: side, height: side),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none.rawValue]
            )
            if let rival {
                // Espejo horizontal para que se miren de frente.
                let context = NSGraphicsContext.current
                context?.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: size.width, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
                transform.concat()
                rival.draw(
                    in: NSRect(x: 0, y: 0, width: side, height: side),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.none.rawValue]
                )
                context?.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
