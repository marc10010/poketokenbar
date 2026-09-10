import CoreGraphics

/// Dónde se planta la ventana del HUD cuando está arrastrada a mano.
///
/// Es geometría pura y vive fuera de AppKit para poder probar el caso de los
/// dos monitores sin tener dos monitores.
public enum HUDPlacement {
    /// Lo que tiene que quedar a la vista para dar una posición por buena:
    /// suficiente para agarrar la ventana y traerla de vuelta.
    public static let minimumVisible = CGSize(width: 80, height: 30)

    public struct Screen: Hashable, Sendable {
        public let frame: CGRect
        /// El `visibleFrame` de AppKit: el marco menos barra de menú y Dock.
        public let visible: CGRect

        public init(frame: CGRect, visible: CGRect) {
            self.frame = frame
            self.visible = visible
        }
    }

    /// La posición guardada, respetada tal cual mientras se vea lo bastante en
    /// **alguna** pantalla.
    ///
    /// Antes esto recortaba siempre contra la primera pantalla que tocara el
    /// marco, y como la principal va la primera de la lista, cruzar el borde
    /// hacia un segundo monitor era imposible: en cuanto la ventana pisaba las
    /// dos, volvía de un salto a la principal. Reencuadrar es solo el rescate
    /// de cuando el sitio guardado ya no existe —desconectas el monitor donde
    /// la dejaste—, no una norma que aplicar en cada movimiento.
    ///
    /// `nil` cuando no queda ninguna pantalla: el que llama vuelve a anclarla
    /// a su esquina.
    public static func free(_ candidate: CGRect, screens: [Screen]) -> CGRect? {
        guard let host = host(of: candidate, screens: screens) else { return nil }
        let seen = host.frame.intersection(candidate)
        if seen.width >= min(minimumVisible.width, candidate.width),
           seen.height >= min(minimumVisible.height, candidate.height) {
            return candidate
        }
        return inside(host.visible, candidate)
    }

    /// La pantalla que más ventana enseña. Con la que "toca primero" bastaría
    /// si no hubiera solapes, pero el caso que importa es justo el del solape.
    private static func host(of candidate: CGRect, screens: [Screen]) -> Screen? {
        let touching = screens
            .map { ($0, $0.frame.intersection(candidate)) }
            .filter { !$0.1.isNull && !$0.1.isEmpty }
        if let best = touching.max(by: { area($0.1) < area($1.1) }) { return best.0 }
        return nil
    }

    private static func inside(_ area: CGRect, _ candidate: CGRect) -> CGRect {
        CGRect(
            x: min(max(candidate.minX, area.minX), max(area.minX, area.maxX - candidate.width)),
            y: min(max(candidate.minY, area.minY), max(area.minY, area.maxY - candidate.height)),
            width: candidate.width,
            height: candidate.height
        )
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
