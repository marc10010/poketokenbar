import PokeTokenBarCore
import SwiftUI

/// Sprite con el pixel art sin suavizar y placeholder mientras baja.
struct SpriteView: View {
    @EnvironmentObject private var sprites: SpriteStore
    let speciesID: Int
    let shiny: Bool
    let size: CGFloat
    var flipped: Bool = false
    /// El multiplicador de los ajustes. Se puede desactivar donde el tamaño lo
    /// manda otra cosa (la barra de menú, que tiene la altura que tiene).
    var scalable: Bool = true

    private var displaySize: CGFloat { scalable ? size * sprites.scale : size }

    var body: some View {
        Group {
            if let image = sprites.image(speciesID: speciesID, shiny: shiny) {
                Image(nsImage: image)
                    .interpolation(sprites.scaling.interpolation)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: flipped ? -1 : 1, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Text("#\(speciesID)")
                            .font(.system(size: max(8, displaySize * 0.22), weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: displaySize, height: displaySize)
    }
}

struct HPBar: View {
    let fraction: Double
    var height: CGFloat = 12

    private var color: Color {
        switch fraction {
        case ..<0.2: return .red
        case ..<0.5: return .yellow
        default: return .green
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: height)
    }
}

struct RarityBadge: View {
    let rarity: Rarity

    private var tint: Color {
        switch rarity {
        case .common: return .gray
        case .uncommon: return .blue
        case .rare: return .purple
        case .legendary: return .orange
        }
    }

    var body: some View {
        Text("\(rarity.badge) \(rarity.label)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Multiplicador de tipos del combate actual. Neutro no se pinta: si no cambia
/// nada, no merece espacio.
struct MatchupBadge: View {
    let matchup: TypeMatchup
    var compact = false

    private var tint: Color {
        if matchup.isImmune { return .red }
        if matchup.raw > 1 { return .green }
        if matchup.raw < 1 { return .orange }
        return .secondary
    }

    var body: some View {
        if !matchup.isNeutral {
            Text(compact ? matchup.badge : "\(matchup.badge) \(matchup.label)")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.18), in: Capsule())
                .foregroundStyle(tint)
                .help(matchup.attacking.map { "Atacando con \($0.capitalized): \(matchup.label)" } ?? matchup.label)
        }
    }
}

struct TypeChips: View {
    let types: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(types, id: \.self) { type in
                Text(TypeStyle.label(type))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TypeStyle.color(type).opacity(0.22), in: Capsule())
            }
        }
    }
}

enum TypeStyle {
    static func color(_ type: String) -> Color {
        switch type {
        case "fire": return .red
        case "water": return .blue
        case "grass": return .green
        case "electric": return .yellow
        case "psychic": return .pink
        case "ice": return .cyan
        case "dragon": return .indigo
        case "dark": return .black
        case "ghost": return .purple
        case "steel": return .gray
        case "fighting": return .orange
        case "poison": return .purple
        case "ground", "rock": return .brown
        case "flying": return .teal
        case "bug": return .mint
        case "fairy": return .pink
        default: return .secondary
        }
    }

    private static let names: [String: String] = [
        "normal": "Normal", "fire": "Fuego", "water": "Agua", "grass": "Planta",
        "electric": "Eléctrico", "ice": "Hielo", "fighting": "Lucha", "poison": "Veneno",
        "ground": "Tierra", "flying": "Volador", "psychic": "Psíquico", "bug": "Bicho",
        "rock": "Roca", "ghost": "Fantasma", "dragon": "Dragón", "dark": "Siniestro",
        "steel": "Acero", "fairy": "Hada",
    ]

    static func label(_ type: String) -> String { names[type] ?? type.capitalized }
}

enum Layout {
    /// Ancho reservado para la barra de scroll flotante de macOS, que se dibuja
    /// encima del contenido y si no tapa lo alineado a la derecha.
    static let scrollGutter: CGFloat = 10
}

struct SectionCard<Content: View>: View {
    @EnvironmentObject private var store: GameStore
    let title: String
    /// Si se puede plegar tocando su cabecera. La clave con la que se recuerda
    /// es el propio título.
    var collapsible = false
    @ViewBuilder var content: Content

    private var collapsed: Bool { collapsible && store.isCollapsed(title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if collapsible {
                Button {
                    store.toggleSection(title)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        heading
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(collapsed ? "Desplegar" : "Plegar")
            } else {
                heading
            }
            if !collapsed {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}
