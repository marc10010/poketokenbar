import PokeTokenBarCore
import SwiftUI

/// Las pestañas del popover. Antes todo esto eran seis acordeones apilados en
/// un scroll de 620 pt: cada mecánica nueva añadía un cajón, y encontrar algo
/// era abrirlos y cerrarlos.
enum AppTab: String, CaseIterable, Identifiable {
    case combate
    case progreso
    case caja
    case pokedex
    case ajustes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .combate: return "Combate"
        case .progreso: return "Progreso"
        case .caja: return "Caja"
        case .pokedex: return "Pokédex"
        case .ajustes: return "Ajustes"
        }
    }

    /// Si la pestaña se encarga ella del scroll. Las rejillas grandes lo
    /// necesitan: así la búsqueda y las cabeceras se quedan fijas y no hay dos
    /// scrolls verticales metidos uno dentro del otro.
    var scrollsItself: Bool {
        switch self {
        case .caja, .pokedex: return true
        case .combate, .progreso, .ajustes: return false
        }
    }

    var icon: String {
        switch self {
        case .combate: return "bolt.fill"
        case .progreso: return "flag.checkered"
        case .caja: return "archivebox.fill"
        case .pokedex: return "book.closed.fill"
        case .ajustes: return "gearshape.fill"
        }
    }
}

/// Barra de pestañas. Iconos con el nombre debajo: cinco caben en 370 pt.
struct TabBar: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = store.selectedTab == tab.rawValue
                Button {
                    store.selectedTab = tab.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.label)
                            .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
}

/// La escalera de desbloqueo, que hasta ahora existía en los datos pero no en
/// ninguna pantalla: estaba repartida entre cuatro secciones.
struct LadderView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.ladder) { step in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: step.reached ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(step.reached ? .green : .secondary)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.requirement.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(step.reached ? .primary : .secondary)
                        ForEach(step.unlocks, id: \.self) { unlock in
                            Text("· \(unlock)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
