import AppKit
import SwiftUI

/// Detector de clic derecho. SwiftUI no distingue botones del ratón: solo
/// ofrece `contextMenu`, que abre un menú. Aquí hace falta que el clic derecho
/// **abra la ficha directamente**, así que se captura el evento en AppKit.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        /// Qué eventos nos quedamos: el clic derecho y el ctrl+clic, que en
        /// macOS es lo mismo. El resto tiene que seguir bajando al botón de
        /// debajo, o el clic izquierdo dejaría de equipar.
        static func shouldIntercept(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return true
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control)
            default:
                return false
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.shouldIntercept(NSApp.currentEvent) ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            // Aquí solo llega si es ctrl+clic, por el hitTest.
            action?()
        }

        /// Sin menú: el clic derecho ya abre la ficha, y si devolviéramos uno
        /// saldría además el menú contextual del panel.
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

extension View {
    /// Abre algo con el clic derecho sin robarle el izquierdo a lo de debajo.
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }
}
