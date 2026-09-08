import PokeTokenBarCore
import SwiftUI

/// Contenido del HUD flotante: los dos sprites, la barra de HP del rival y los
/// números. Sin fondo propio salvo un velo muy tenue para que el pixel art se
/// lea igual sobre un editor claro o oscuro.
struct HUDView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        if let encounter = store.state.encounter,
           let rival = store.pokedex[encounter.speciesID],
           let companion = store.state.activeCompanion,
           let form = store.activeForm {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SpriteView(speciesID: form.id, shiny: companion.isShiny, size: 30)
                    Text("vs")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    SpriteView(speciesID: rival.id, shiny: encounter.isShiny, size: 30, flipped: true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(rival.localizedName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            if encounter.isShiny {
                                Text("✦").font(.system(size: 8)).foregroundStyle(.yellow)
                            }
                        }
                        Text(encounter.rarity.badge)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                HPBar(fraction: encounter.hpFraction, height: 5)
                Text("\(Fmt.compact(encounter.currentHP)) / \(Fmt.compact(encounter.maxHP))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .opacity(0.55)
            )
            .padding(4)
            .frame(maxWidth: .infinity, alignment: horizontalAlignment)
        }
    }

    private var horizontalAlignment: Alignment {
        switch store.state.settings.hudCorner {
        case .topRight, .bottomRight: return .trailing
        case .topLeft, .bottomLeft: return .leading
        }
    }
}
