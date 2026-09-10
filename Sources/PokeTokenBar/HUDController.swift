import AppKit
import Combine
import PokeTokenBarCore
import SwiftUI

/// HUD flotante. Dos modos de colocación:
/// - anclado a una esquina: **una ventana por pantalla**, porque con varios
///   monitores anclarlo solo a la principal lo deja donde no estás mirando;
/// - arrastrado a mano: una sola ventana en la posición guardada.
///
/// Bloqueado es click-through (se ve, no estorba). Desbloqueado acepta clics:
/// se arrastra y su menú contextual permite cambiar de compañero sin depender
/// del ítem de la barra de menú, que en barras llenas puede quedar oculto.
@MainActor
final class HUDController {
    private static let baseBattleSize = NSSize(width: 268, height: 104)
    private static let basePickerSize = NSSize(width: 336, height: 112)
    /// Lado del sprite de la cabecera: es lo que crece con el ajuste, así que
    /// es la medida con la que hay que agrandar el panel.
    private static let headerSpriteSide: CGFloat = 42
    private static let maxSize = NSSize(width: 620, height: 760)
    private static let margin: CGFloat = 12

    private let store: GameStore
    private let sprites: SpriteStore
    private var panels: [NSPanel] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Evita el bucle mover→guardar→mover al reposicionar por código.
    private var isRepositioning = false

    init(store: GameStore, sprites: SpriteStore) {
        self.store = store
        self.sprites = sprites

        // `@Published` emite en `willSet`: dentro del sink `store.state` sigue
        // siendo el valor viejo, así que hay que usar el que llega.
        store.$state
            .removeDuplicates { $0.settings == $1.settings && $0.hasStarter == $1.hasStarter }
            .sink { [weak self] state in self?.sync(state) }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSWindow.didMoveNotification)
            .compactMap { $0.object as? NSPanel }
            .sink { [weak self] panel in self?.panelDidMove(panel) }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSWindow.didResizeNotification)
            .compactMap { $0.object as? NSPanel }
            .sink { [weak self] panel in self?.panelDidResize(panel) }
            .store(in: &cancellables)

        sync()
    }

    /// El selector de inicial siempre necesita clics: es la entrada al juego.
    private func interactive(_ state: GameState) -> Bool { !state.hasStarter }

    private func acceptsMouse(_ state: GameState) -> Bool {
        interactive(state) || !state.settings.hudLocked
    }

    func sync(_ incoming: GameState? = nil) {
        let state = incoming ?? store.state
        guard state.settings.hudEnabled else {
            teardown()
            return
        }

        let interactive = interactive(state)
        let acceptsMouse = acceptsMouse(state)
        let frames = targetFrames(state)
        rememberFreeOrigin(frames.first, state)
        if panels.count != frames.count {
            teardown()
            panels = frames.map { _ in makePanel() }
        }

        // Guardar el sitio nuevo vuelve a entrar aquí, así que la bandera se
        // restaura en vez de apagarse: apagarla dejaría al que llamó fuera de
        // su propia protección.
        let wasRepositioning = isRepositioning
        isRepositioning = true
        let minimum = battleSize(state)
        for (panel, frame) in zip(panels, frames) {
            panel.contentMinSize = minimum
            panel.ignoresMouseEvents = !acceptsMouse
            panel.isMovableByWindowBackground = acceptsMouse && !interactive
            panel.alphaValue = interactive ? 1 : state.settings.hudOpacity
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.orderFrontRegardless()
        }
        isRepositioning = wasRepositioning

        Diagnostics.append(
            "hud: \(panels.count) panel(es) · interactivo=\(interactive) · movible=\(acceptsMouse && !interactive) · "
                + "libre=\(state.settings.hudFreeOrigin != nil) · "
                + panels.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY))" }.joined(separator: " | ")
        )
    }

    /// Cierra los paneles. Soltar el controlador no basta: las ventanas las
    /// retiene AppKit hasta que se les dice que salgan.
    func shutdown() {
        teardown()
    }

    private func teardown() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    /// Guarda la posición tras arrastrar, para que sobreviva a reinicios.
    private func panelDidMove(_ panel: NSPanel) {
        guard !isRepositioning, panels.contains(panel) else { return }
        let origin = panel.frame.origin
        store.updateSettings { $0.hudFreeOrigin = HUDOrigin(x: origin.x, y: origin.y) }
    }

    /// Guarda el tamaño tras redimensionar, para que el despliegue persista.
    private func panelDidResize(_ panel: NSPanel) {
        guard !isRepositioning, panels.contains(panel), store.state.hasStarter else { return }
        let size = panel.frame.size
        let minimum = battleSize(store.state)
        let compact = abs(size.width - minimum.width) < 2 && abs(size.height - minimum.height) < 2
        store.updateSettings {
            $0.hudSize = compact ? nil : HUDSize(width: size.width, height: size.height)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.basePickerSize),
            // .resizable en una ventana sin marco: los bordes arrastran aunque
            // no se dibuje ningún tirador.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMaxSize = Self.maxSize
        panel.contentView = NSHostingView(
            rootView: HUDView()
                .environmentObject(store)
                .environmentObject(sprites)
        )
        return panel
    }

    /// Cuánto crece el panel por el multiplicador de sprites.
    private func extraForSprites(_ state: GameState) -> CGFloat {
        Self.headerSpriteSide * CGFloat(max(0, state.settings.spriteScale - 1))
    }

    private func battleSize(_ state: GameState) -> NSSize {
        let extra = extraForSprites(state)
        return NSSize(
            width: Self.baseBattleSize.width + extra * 2,
            height: Self.baseBattleSize.height + extra
        )
    }

    private func pickerSize(_ state: GameState) -> NSSize {
        let extra = extraForSprites(state)
        return NSSize(
            width: Self.basePickerSize.width + extra * 6,
            height: Self.basePickerSize.height + extra
        )
    }

    private func size(_ state: GameState) -> NSSize {
        guard !interactive(state) else { return pickerSize(state) }
        let minimum = battleSize(state)
        guard let stored = state.settings.hudSize else { return minimum }
        return NSSize(
            width: min(max(stored.width, minimum.width), Self.maxSize.width),
            height: min(max(stored.height, minimum.height), Self.maxSize.height)
        )
    }

    /// Una posición si está arrastrado a mano; una por pantalla si está anclado.
    private func targetFrames(_ state: GameState) -> [NSRect] {
        if let free = state.settings.hudFreeOrigin, let frame = clamped(free, state) {
            // Desplegar y plegar dejan quieta la esquina de arriba a la
            // izquierda. Sin esto la ventana crece hacia arriba, porque el
            // origen de Cocoa es la esquina de abajo.
            if let panel = panels.first, panel.frame.size != frame.size {
                return [HUDPlacement.resized(panel.frame, to: frame.size, screens: screenList())]
            }
            return [frame]
        }
        return NSScreen.screens.map { cornerFrame(on: $0, state) }
    }

    /// Guarda el sitio que deja un despliegue: si no, al reiniciar la ventana
    /// volvería al origen viejo, el de antes de desplegar.
    ///
    /// El salto de turno no es adorno: `@Published` emite en `willSet`, así que
    /// escribir aquí mismo se pierde cuando aterriza la asignación que nos
    /// trajo. Al turno siguiente el estado ya es el nuevo y la escritura pega.
    private func rememberFreeOrigin(_ frame: NSRect?, _ state: GameState) {
        guard let frame, let free = state.settings.hudFreeOrigin else { return }
        guard abs(free.x - frame.minX) > 0.5 || abs(free.y - frame.minY) > 0.5 else { return }
        let origin = HUDOrigin(x: frame.minX, y: frame.minY)
        RunLoop.main.perform { [weak self] in
            // `perform` corre en el hilo principal, pero su cierre es
            // `@Sendable` y el compilador no lo sabe.
            MainActor.assumeIsolated {
                guard let self, self.store.state.settings.hudFreeOrigin != nil else { return }
                self.store.updateSettings { $0.hudFreeOrigin = origin }
            }
        }
    }

    /// Mantiene la ventana dentro de alguna pantalla: si desconectas el
    /// monitor donde la dejaste, no se queda en el limbo. La regla está en
    /// `HUDPlacement`, sin AppKit, para poder probarla.
    private func clamped(_ origin: HUDOrigin, _ state: GameState) -> NSRect? {
        let candidate = NSRect(origin: NSPoint(x: origin.x, y: origin.y), size: size(state))
        return HUDPlacement.free(candidate, screens: screenList())
    }

    private func screenList() -> [HUDPlacement.Screen] {
        NSScreen.screens.map { .init(frame: $0.frame, visible: $0.visibleFrame) }
    }

    /// `visibleFrame` ya descuenta barra de menú y Dock de esa pantalla.
    private func cornerFrame(on screen: NSScreen, _ state: GameState) -> NSRect {
        let area = screen.visibleFrame
        let size = size(state)
        let margin = Self.margin

        let origin: NSPoint
        switch state.settings.hudCorner {
        case .topLeft:
            origin = NSPoint(x: area.minX + margin, y: area.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: area.minX + margin, y: area.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: area.maxX - size.width - margin, y: area.minY + margin)
        }
        return NSRect(origin: origin, size: size)
    }
}
