import PokeTokenBarCore
import SwiftUI

/// Caja PC apilada por forma visible: un hueco por forma con contador "×N", en
/// orden Pokédex. Así la rejilla tiene techo (251 especies) por muchas capturas
/// que acumules.
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
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.speciesCaught) de 251 especies · \(Fmt.tokens(store.state.box.count)) capturas")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(store.boxGroups) { group in
                            cell(group)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 190)
            }
        }
    }

    private func cell(_ group: BoxGroup) -> some View {
        let isActive = store.activeGroupID == group.id
        return Button {
            store.setActiveCompanion(group.representative.id)
        } label: {
            VStack(spacing: 0) {
                SpriteView(speciesID: group.form.id, shiny: group.isShiny, size: 44)
                Text(group.form.localizedName)
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
                if group.isShiny {
                    Text("✦").font(.system(size: 8)).foregroundStyle(.yellow).padding(2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if group.count > 1 {
                    Text("×\(group.count)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.22), in: Capsule())
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(group.form.localizedName)\(group.isShiny ? " ✦" : "") · \(group.count) en la caja · #\(String(format: "%03d", group.form.id))")
    }
}
