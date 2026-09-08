import PokeTokenBarCore
import SwiftUI

/// Rejilla de la caja PC apilada por forma visible. La comparten el popover y
/// el HUD expandido; las columnas son adaptativas para que crezcan al ensanchar.
struct BoxGridView: View {
    @EnvironmentObject private var store: GameStore

    var cellSize: CGFloat = 44
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                Text("\(store.speciesCaught) de 251 especies · \(Fmt.tokens(store.state.box.count)) capturas")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellSize + 8), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(store.boxGroups) { group in
                        cell(group)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cell(_ group: BoxGroup) -> some View {
        let isActive = store.activeGroupID == group.id
        return Button {
            store.setActiveCompanion(group.representative.id)
        } label: {
            VStack(spacing: 0) {
                SpriteView(speciesID: group.displayForm.id, shiny: group.isShiny, size: cellSize)
                Text(group.displayForm.localizedName)
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
            .overlay(alignment: .topLeading) {
                if group.hasEvolved {
                    Text(group.stage == .two ? "★★" : "★")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .padding(2)
                }
            }
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
        .help(
            "\(group.displayForm.localizedName)\(group.isShiny ? " ✦" : "") · \(group.count) en la caja · "
                + "#\(String(format: "%03d", group.species.id)) \(group.species.localizedName)"
                + (group.hasEvolved ? " · \(group.stage.label)" : "")
                + (isActive ? " · equipado" : "")
        )
    }
}
