import PokeTokenBarCore
import SwiftUI

/// Caja PC: todo lo capturado. Al pulsar, se equipa como compañero activo.
struct PCBoxView: View {
    @EnvironmentObject private var store: GameStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        if store.state.box.isEmpty {
            Text("Vacía. Reduce el HP de un rival a 0 para capturarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(store.box) { captured in
                        let form = store.form(of: captured)
                        let isActive = store.state.activeCompanion?.id == captured.id
                        Button {
                            store.setActiveCompanion(captured.id)
                        } label: {
                            VStack(spacing: 0) {
                                SpriteView(speciesID: form.id, shiny: captured.isShiny, size: 44)
                                Text(form.localizedName)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.07))
                            )
                            .overlay(alignment: .topTrailing) {
                                if captured.isShiny {
                                    Text("✦").font(.system(size: 8)).foregroundStyle(.yellow).padding(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("\(form.localizedName) · capturado con \(Fmt.tokens(captured.capturedAtTotalTokens)) tokens")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 190)
        }
    }
}
