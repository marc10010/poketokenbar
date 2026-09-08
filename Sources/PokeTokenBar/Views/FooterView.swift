import PokeTokenBarCore
import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var sources: TokenSourceCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources.descriptions, id: \.name) { source in
                HStack(spacing: 5) {
                    Circle()
                        .fill(source.healthy ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(source.name).font(.system(size: 10, weight: .medium))
                    Text(source.status).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { store.state.settings.countCacheTokens },
                set: { newValue in store.updateSettings { $0.countCacheTokens = newValue } }
            )) {
                Text("Contar tokens de caché como daño").font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Salir") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Text("1 token = 1 HP").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}
