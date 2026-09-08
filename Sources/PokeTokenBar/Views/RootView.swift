import PokeTokenBarCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(spacing: 0) {
            if store.state.hasStarter {
                BattleDashboardView()
            } else {
                StarterPickerView()
            }
        }
        .frame(width: 360)
    }
}
