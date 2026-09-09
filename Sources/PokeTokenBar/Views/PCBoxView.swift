import PokeTokenBarCore
import SwiftUI

/// La caja en el popover: la ficha del hueco elegido fijada arriba y la
/// rejilla debajo, que se queda donde estaba. Antes la ficha sustituía a la
/// rejilla, así que mirar dos Pokémon seguidos era perder el sitio dos veces.
struct PCBoxView: View {
    @EnvironmentObject private var store: GameStore

    private var selected: BoxGroup? {
        guard let id = store.selectedBoxGroupID else { return nil }
        return store.boxGroups.first(where: { $0.id == id })
    }

    var body: some View {
        if store.state.box.isEmpty {
            Text("Vacía. Reduce el HP de un rival a 0 para capturarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let selected {
                    PokemonDetailView(group: selected, compact: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    Divider()
                }
                // Sin techo de altura: la caja es su propia pestaña y el hueco
                // que no ocupa la ficha es suyo.
                BoxGridView()
            }
        }
    }
}
