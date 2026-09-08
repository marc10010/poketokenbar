import AppKit
import PokeTokenBarCore
import SwiftUI

/// Sprite animado. `Image(nsImage:)` de SwiftUI pinta solo el primer fotograma
/// de un GIF, así que hay que envolver un `NSImageView`, que sí anima.
struct AnimatedSpriteView: View {
    @EnvironmentObject private var sprites: SpriteStore
    let speciesID: Int
    let shiny: Bool
    let size: CGFloat
    var flipped = false
    /// Las fichas escalan con el ajuste; una rejilla no, que ahí manda la
    /// cuadrícula.
    var scalable = true

    private var displaySize: CGFloat { scalable ? size * sprites.scale : size }

    var body: some View {
        Group {
            if let image = sprites.image(speciesID: speciesID, shiny: shiny, animated: true) {
                GIFView(image: image, scaling: sprites.scaling)
                    .scaleEffect(x: flipped ? -1 : 1, y: 1)
            } else {
                // Mientras baja el animado, el estático ya cacheado.
                SpriteView(speciesID: speciesID, shiny: shiny, size: displaySize, flipped: flipped)
            }
        }
        .frame(width: displaySize, height: displaySize)
    }
}

extension SpriteScaling {
    /// SwiftUI, para los sprites estáticos.
    var interpolation: Image.Interpolation {
        switch self {
        case .pixel: return .none
        case .medio: return .medium
        case .suave: return .high
        }
    }

    /// CALayer, para los GIF animados dentro del NSImageView.
    var magnificationFilter: CALayerContentsFilter {
        switch self {
        case .pixel: return .nearest
        case .medio: return .linear
        case .suave: return .trilinear
        }
    }
}

private struct GIFView: NSViewRepresentable {
    let image: NSImage
    let scaling: SpriteScaling

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        view.layer?.magnificationFilter = scaling.magnificationFilter
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image { nsView.image = image }
        nsView.animates = true
        nsView.layer?.magnificationFilter = scaling.magnificationFilter
    }
}
