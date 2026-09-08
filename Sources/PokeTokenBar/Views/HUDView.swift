import PokeTokenBarCore
import SwiftUI

/// Contenido del HUD flotante. Tiene dos modos:
/// - sin compañero: tira compacta para elegir inicial (interactiva), porque el
///   ítem de la barra de menú puede quedar oculto en barras llenas o con notch;
/// - en combate: sprites, barra de HP y números, sin fondo apenas.
struct HUDView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        Group {
            if store.state.hasStarter {
                battle
            } else {
                starterPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
    }

    private var starterPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PokeTokenBar · elige tu compañero")
                .font(.system(size: 10, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(store.pokedex.starters) { starter in
                    Button {
                        store.chooseStarter(speciesID: starter.id)
                    } label: {
                        SpriteView(speciesID: starter.id, shiny: false, size: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(starter.localizedName)
                }
            }
            Text("\(Fmt.tokens(store.totalTokens)) tokens acumulados")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(4)
    }

    @ViewBuilder
    private var battle: some View {
        if let encounter = store.state.encounter,
           let rival = store.pokedex[encounter.speciesID],
           let companion = store.state.activeCompanion,
           let form = store.activeForm {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SpriteView(speciesID: form.id, shiny: companion.isShiny, size: 30)
                    Text("vs")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    SpriteView(speciesID: rival.id, shiny: encounter.isShiny, size: 30, flipped: true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(rival.localizedName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            if encounter.isShiny {
                                Text("✦").font(.system(size: 8)).foregroundStyle(.yellow)
                            }
                        }
                        Text(encounter.rarity.badge)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                HPBar(fraction: encounter.hpFraction, height: 5)
                Text("\(Fmt.compact(encounter.currentHP)) / \(Fmt.compact(encounter.maxHP))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            )
            .padding(4)
            .contextMenu { hudMenu }
        }
    }

    /// Menú contextual del HUD: cambiar compañero y colocación sin pasar por
    /// el ítem de la barra de menú.
    @ViewBuilder
    private var hudMenu: some View {
        // Solo los últimos grupos: el menú no puede crecer con las capturas.
        let recent = store.boxGroups
            .sorted { $0.latestCapturedAt > $1.latestCapturedAt }
            .prefix(8)
        if store.boxGroups.count > 1 {
            Text("Compañero")
            ForEach(Array(recent)) { group in
                Button {
                    store.setActiveCompanion(group.representative.id)
                } label: {
                    Text(group.form.localizedName + (group.isShiny ? " ✦" : "")
                        + (group.count > 1 ? " ×\(group.count)" : "")
                        + (store.activeGroupID == group.id ? "  ✓" : ""))
                }
            }
            Button("Caja PC completa (\(store.speciesCaught)/251)…") {
                NotificationCenter.default.post(name: .poketokenbarShowPopover, object: nil)
            }
            Divider()
        }

        if store.state.settings.hudFreeOrigin != nil {
            Button("Volver a la esquina") {
                store.updateSettings { $0.hudFreeOrigin = nil }
            }
        }
        Button(store.state.settings.hudLocked ? "Desbloquear (poder moverlo)" : "Bloquear en su sitio") {
            store.updateSettings { $0.hudLocked.toggle() }
        }
        Button("Ocultar el HUD") {
            store.updateSettings { $0.hudEnabled = false }
        }
        Divider()
        Button("Salir de PokeTokenBar") { NSApplication.shared.terminate(nil) }
    }

    private var horizontalAlignment: Alignment {
        switch store.state.settings.hudCorner {
        case .topRight, .bottomRight: return .trailing
        case .topLeft, .bottomLeft: return .leading
        }
    }
}
