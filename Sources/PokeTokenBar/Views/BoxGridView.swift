import PokeTokenBarCore
import SwiftUI

/// Rejilla de la caja PC apilada por forma visible. La comparten el popover y
/// el HUD expandido; las columnas son adaptativas para que crezcan al ensanchar.
struct BoxGridView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var sprites: SpriteStore

    var cellSize: CGFloat = 52
    var showsToolbar = true
    var compactToolbar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsToolbar {
                BoxToolbar(compact: compactToolbar)
            }
            if store.filteredBoxGroups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cellSize * sprites.scale + 8), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(store.filteredBoxGroups) { group in
                            cell(group)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, Layout.scrollGutter)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nada coincide con la búsqueda.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Limpiar filtros") { store.boxFilter.reset() }
                .buttonStyle(.link)
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func tooltip(for group: BoxGroup, isActive: Bool) -> String {
        var parts: [String] = [group.displayForm.localizedName]
        if group.isShiny { parts.append("✦") }
        parts.append("· #\(String(format: "%03d", group.species.id)) \(group.species.localizedName)")
        if group.hasEvolved { parts.append("· \(group.stage.label)") }
        if isActive { parts.append("· equipado") }
        let wins = store.timesDefeated(familyOf: group.species.id)
        if wins > 0 { parts.append("· \(wins) victorias contra su línea") }
        parts.append("· clic para enviarlo a luchar, clic derecho para su ficha")
        return parts.joined(separator: " ")
    }

    private func cell(_ group: BoxGroup) -> some View {
        let isActive = store.activeGroupID == group.id
        return Button {
            store.setActiveCompanion(group.representative.id)
        } label: {
            VStack(spacing: 0) {
                SpriteView(speciesID: group.displayForm.id, shiny: group.displaysShiny, size: cellSize)
                Text(group.displayForm.localizedName)
                    .font(.system(size: 10))
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
                    Text("✦").font(.system(size: 10)).foregroundStyle(.yellow).padding(2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Ya no puede haber repetidos, así que el hueco lo ocupa el
                // número que sí crece: victorias contra esa línea.
                let wins = store.timesDefeated(familyOf: group.species.id)
                if wins > 1 {
                    Text("\(wins)⚔")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.22), in: Capsule())
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .onRightClick { store.selectedBoxGroupID = group.id }
        .help(tooltip(for: group, isActive: isActive))
    }
}
