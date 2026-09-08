import AppKit
import Combine
import PokeTokenBarCore
import SwiftUI

/// Ventana flotante sin bordes anclada a una esquina. Es click-through
/// (`ignoresMouseEvents`) a propósito: se ve siempre, no roba foco y no tapa
/// nada con lo que puedas querer interactuar.
@MainActor
final class HUDController {
    private static let size = NSSize(width: 208, height: 76)
    private static let margin: CGFloat = 12

    private let store: GameStore
    private let sprites: SpriteStore
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(store: GameStore, sprites: SpriteStore) {
        self.store = store
        self.sprites = sprites

        store.$state
            .map { ($0.settings.hudEnabled, $0.settings.hudCorner, $0.settings.hudOpacity, $0.hasStarter) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        sync()
    }

    private func sync() {
        let settings = store.state.settings
        guard settings.hudEnabled, store.state.hasStarter else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = settings.hudOpacity
        reposition()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // Visible en todos los escritorios y encima de apps a pantalla completa.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: HUDView()
                .environmentObject(store)
                .environmentObject(sprites)
        )
        return panel
    }

    /// Ancla en la esquina usando `visibleFrame`, que ya descuenta barra de
    /// menú y Dock.
    private func reposition() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let size = Self.size
        let margin = Self.margin

        let origin: NSPoint
        switch store.state.settings.hudCorner {
        case .topLeft:
            origin = NSPoint(x: area.minX + margin, y: area.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: area.minX + margin, y: area.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: area.maxX - size.width - margin, y: area.minY + margin)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
