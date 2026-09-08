import PokeTokenBarCore
import SwiftUI

struct PCBoxView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        if store.state.box.isEmpty {
            Text("Vacía. Reduce el HP de un rival a 0 para capturarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            BoxGridView()
                .frame(maxHeight: 190)
        }
    }
}
