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

    var body: some View {
        Group {
            if let image = sprites.image(speciesID: speciesID, shiny: shiny, animated: true) {
                GIFView(image: image)
                    .scaleEffect(x: flipped ? -1 : 1, y: 1)
            } else {
                // Mientras baja el animado, el estático ya cacheado.
                SpriteView(speciesID: speciesID, shiny: shiny, size: size, flipped: flipped)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct GIFView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        // Sin esto el escalado suaviza el pixel art y parece borroso.
        view.layer?.magnificationFilter = .nearest
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image { nsView.image = image }
        nsView.animates = true
        nsView.layer?.magnificationFilter = .nearest
    }
}
