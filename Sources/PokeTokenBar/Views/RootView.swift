import PokeTokenBarCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        // Acotado y con scroll: con una ficha abierta el contenido pasa de
        // 1000 pt y no cabría en la pantalla de un portátil.
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if store.state.hasStarter {
                    BattleDashboardView()
                } else {
                    StarterPickerView()
                }
            }
            .padding(.trailing, Layout.scrollGutter)
        }
        .frame(width: 360 + Layout.scrollGutter)
        .frame(maxHeight: 620)
    }
}
