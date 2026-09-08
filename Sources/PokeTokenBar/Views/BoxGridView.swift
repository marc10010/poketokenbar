import PokeTokenBarCore
import SwiftUI

/// La caja PC. La comparten el popover y el HUD expandido.
///
/// Está partida en tramos con cabecera pegajosa porque el techo de la caja son
/// 258 huecos (129 líneas evolutivas × normal y shiny) y una rejilla plana de
/// ese tamaño no se navega: solo se busca lo que ya sabes que tienes.
struct BoxGridView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var sprites: SpriteStore

    var cellSize: CGFloat = 52
    var showsToolbar = true
    var compactToolbar = false

    @State private var columns = 1
    @FocusState private var focused: Bool

    private var density: BoxDensity { store.state.settings.boxDensity }

    private var cellWidth: CGFloat { cellSize * sprites.scale + 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fuera del scroll a propósito: buscar es lo que se hace cuando la
            // caja es grande, y no puede irse hacia arriba con el contenido.
            if showsToolbar {
                BoxToolbar(compact: compactToolbar)
            }
            if store.filteredBoxGroups.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(store.boxSections) { section in
                        Section {
                            body(of: section)
                        } header: {
                            header(section)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, Layout.scrollGutter)
                .background(widthReader)
            }
            .focusable()
            .focused($focused)
            .onMoveCommand { direction in
                guard let moved = store.moveBoxSelection(move(direction), columns: density == .lista ? 1 : columns)
                else { return }
                withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(moved, anchor: .center) }
            }
            .onExitCommand { store.closeDetail() }
        }
    }

    /// Cuántas columnas caben de verdad, que es lo que necesitan las flechas
    /// para que subir y bajar caigan donde se ve.
    private var widthReader: some View {
        GeometryReader { geometry in
            Color.clear.onChange(of: geometry.size.width) { width in
                columns = max(1, Int(width / (cellWidth + 6)))
            }
            .onAppear { columns = max(1, Int(geometry.size.width / (cellWidth + 6))) }
        }
    }

    private func move(_ direction: MoveCommandDirection) -> BoxMove {
        switch direction {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        @unknown default: return .right
        }
    }

    @ViewBuilder
    private func body(of section: BoxSection) -> some View {
        switch density {
        case .rejilla:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 6)], spacing: 6) {
                ForEach(section.groups) { group in
                    cell(group).id(group.id)
                }
            }
        case .lista:
            VStack(spacing: 2) {
                ForEach(section.groups) { group in
                    row(group).id(group.id)
                }
            }
        }
    }

    private func header(_ section: BoxSection) -> some View {
        HStack(spacing: 5) {
            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(section.groups.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(.regularMaterial)
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
        parts.append("· clic para su ficha, doble clic para enviarlo a luchar")
        return parts.joined(separator: " ")
    }

    /// Clic simple abre la ficha y doble clic equipa. Antes era al revés, con
    /// el clic izquierdo cambiando de compañero y la ficha escondida en el
    /// clic derecho: mirar es lo que se hace todo el rato y cambiar de
    /// compañero cambia el daño por token, así que lo barato va en el gesto
    /// barato.
    private func select(_ group: BoxGroup) -> some Gesture {
        TapGesture(count: 2)
            .onEnded { store.setActiveCompanion(group.representative.id) }
            .exclusively(
                before: TapGesture()
                    .onEnded {
                        store.selectedBoxGroupID = group.id
                        focused = true
                    }
            )
    }

    private func cell(_ group: BoxGroup) -> some View {
        let isActive = store.activeGroupID == group.id
        let isSelected = store.selectedBoxGroupID == group.id
        return VStack(spacing: 0) {
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
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
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
        .overlay(alignment: .bottomLeading) {
            if isActive {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.accentColor)
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .gesture(select(group))
        .onRightClick { store.selectedBoxGroupID = group.id }
        .help(tooltip(for: group, isActive: isActive))
        .accessibilityElement()
        .accessibilityLabel(tooltip(for: group, isActive: isActive))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Fila con los números a la vista. La caja guarda más dato por Pokémon
    /// que ninguna otra pantalla y en rejilla solo cabía el sprite.
    private func row(_ group: BoxGroup) -> some View {
        let isActive = store.activeGroupID == group.id
        let isSelected = store.selectedBoxGroupID == group.id
        let wins = store.timesDefeated(familyOf: group.species.id)
        return HStack(spacing: 8) {
            SpriteView(speciesID: group.displayForm.id, shiny: group.displaysShiny, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(group.displayForm.localizedName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if group.isShiny { Text("✦").font(.system(size: 9)).foregroundStyle(.yellow) }
                    if isActive {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("#\(String(format: "%03d", group.displayForm.id)) · \(group.stage.label) · \(group.species.rarity.label)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Fmt.compact(group.representative.tokensEarned)) tk")
                    .font(.system(size: 9, design: .monospaced))
                Text(wins > 0 ? "\(wins)⚔" : "—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(Rectangle())
        .gesture(select(group))
        .onRightClick { store.selectedBoxGroupID = group.id }
        .help(tooltip(for: group, isActive: isActive))
        .accessibilityElement()
        .accessibilityLabel(tooltip(for: group, isActive: isActive))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
