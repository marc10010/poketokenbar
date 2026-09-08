import PokeTokenBarCore
import SwiftUI

/// Primer arranque: elegir inicial. Se ofrecen los seis clásicos de Gen 1 y 2;
/// el resto de la Pokédex llega capturando.
struct StarterPickerView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Elige tu compañero")
                    .font(.headline)
                Text("Cada token que gastes en la API es un punto de daño. Tu compañero evoluciona con tu histórico acumulado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(store.pokedex.starters) { starter in
                    Button {
                        store.chooseStarter(speciesID: starter.id)
                    } label: {
                        VStack(spacing: 2) {
                            SpriteView(speciesID: starter.id, shiny: false, size: 64)
                            Text(starter.localizedName)
                                .font(.caption.weight(.semibold))
                            Text("Gen \(starter.generation)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.totalTokens > 0 {
                Text("Ya llevas \(Fmt.tokens(store.totalTokens)) tokens contabilizados; empezarán a hacer daño en cuanto elijas.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            FooterView()
        }
        .padding(14)
    }
}
