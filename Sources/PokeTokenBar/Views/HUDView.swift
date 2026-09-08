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
            if !store.state.hasStarter {
                starterPicker
            } else if let celebration = store.lastMedal {
                medalPanel(celebration)
            } else if let active = store.activeMilestone {
                bossPanel(border: .purple) {
                    MilestoneCardView(milestone: active.milestone, battle: active.battle, compact: true)
                }
            } else if let active = store.activeGym {
                gymPanel(gym: active.gym, battle: active.battle)
            } else {
                battle
            }
        }
    }

    private var starterPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PokeTokenBar · elige tu compañero")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(store.pokedex.starters) { starter in
                    Button {
                        store.chooseStarter(speciesID: starter.id)
                    } label: {
                        SpriteView(speciesID: starter.id, shiny: false, size: 46)
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
                .font(.system(size: 11, design: .monospaced))
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

    /// Alturas a las que el HUD va revelando contenido al crecer.
    static let metricsThreshold: CGFloat = 140
    static let boxThreshold: CGFloat = 248

    static func showsMetrics(forHeight height: CGFloat) -> Bool { height >= metricsThreshold }
    static func showsBox(forHeight height: CGFloat) -> Bool { height >= boxThreshold }

    /// La caja dentro del HUD: ficha si hay una abierta, rejilla si no.
    @ViewBuilder
    private var boxSection: some View {
        if store.inspectingRival, let encounter = store.state.encounter, let rival = store.rivalSpecies {
            ScrollView {
                RivalDetailView(encounter: encounter, species: rival)
                    .padding(.trailing, Layout.scrollGutter)
            }
        } else if store.state.box.isEmpty {
            Text("Caja vacía todavía.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if let selected = store.selectedBoxGroupID,
                  let group = store.boxGroups.first(where: { $0.id == selected }) {
            ScrollView {
                PokemonDetailView(group: group)
                    .padding(.trailing, Layout.scrollGutter)
            }
        } else {
            BoxGridView(cellSize: 46, compactToolbar: true)
        }
    }

    @ViewBuilder
    private var battle: some View {
        if let encounter = store.state.encounter,
           let rival = store.pokedex[encounter.speciesID],
           let companion = store.state.activeCompanion,
           let form = store.activeForm {
            GeometryReader { geometry in
                let showsMetrics = Self.showsMetrics(forHeight: geometry.size.height)
                let showsBox = Self.showsBox(forHeight: geometry.size.height)
                VStack(alignment: .leading, spacing: 5) {
                    battleHeader(
                        encounter: encounter,
                        rival: rival,
                        companion: companion,
                        form: form,
                        expanded: showsMetrics || showsBox,
                        panelHeight: geometry.size.height
                    )
                    if showsMetrics {
                        Divider()
                        metricsStrip
                    }
                    if showsBox {
                        Divider()
                        boxSection
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                )
                .contextMenu { hudMenu }
            }
            .padding(4)
        }
    }

    /// Métricas de consumo en el HUD desplegado, en el mismo orden que el
    /// popover para que no haya dos verdades distintas.
    private var metricsStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            metric("Tokens totales", Fmt.tokens(store.totalTokens))
            metric("Este mes", Fmt.tokens(store.monthTokens))
            metric("Medallas", "\(store.medals)/16 · \(store.rank.label)")
            metric("Daño por token", store.currentMatchup.isNeutral ? "×1" : "\(store.currentMatchup.badge) · \(store.currentMatchup.label)")
            metric("Especies", "\(store.speciesCaught) / 251")
            metric("Capturas", Fmt.tokens(store.state.box.count))
            if let next = store.activeNextForm, let remaining = store.stage.tokensToNext(from: store.activeTokensEarned) {
                metric("\(next.localizedName) en", Fmt.tokens(remaining))
            } else {
                metric("Evolución", store.stage.label)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    /// Abre una ficha y, si el panel está plegado, lo despliega: si no, el clic
    /// dejaría estado abierto que no se ve en ninguna parte.
    private func openDetail(rival: Bool, panelHeight: CGFloat) {
        store.inspectingRival = rival
        store.selectedBoxGroupID = rival ? nil : store.activeGroupID
        guard !Self.showsBox(forHeight: panelHeight) else { return }
        store.updateSettings { $0.hudSize = HUDSize(width: 380, height: 460) }
    }

    private func battleHeader(
        encounter: WildEncounter,
        rival: Pokemon,
        companion: CapturedPokemon,
        form: Pokemon,
        expanded: Bool,
        panelHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button {
                    openDetail(rival: false, panelHeight: panelHeight)
                } label: {
                    SpriteView(speciesID: form.id, shiny: companion.displaysShiny, size: 42)
                }
                .buttonStyle(.plain)
                .onRightClick { openDetail(rival: false, panelHeight: panelHeight) }
                .help("Ver la ficha de \(form.localizedName)")
                Text("vs")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Button {
                    openDetail(rival: true, panelHeight: panelHeight)
                } label: {
                    SpriteView(speciesID: rival.id, shiny: encounter.isShiny, size: 42, flipped: true)
                }
                .buttonStyle(.plain)
                .onRightClick { openDetail(rival: true, panelHeight: panelHeight) }
                .help("Ver la ficha de \(rival.localizedName)")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(rival.localizedName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if encounter.isShiny {
                            Text("✦").font(.system(size: 11)).foregroundStyle(.yellow)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(encounter.rarity.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        MatchupBadge(matchup: store.currentMatchup, compact: true)
                    }
                }
                Spacer(minLength: 2)
                resizeButton(expanded: expanded)
            }
            HPBar(fraction: encounter.hpFraction, height: 8)
            Text("\(Fmt.tokens(encounter.currentHP)) / \(Fmt.tokens(encounter.maxHP)) HP")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// Además de arrastrar los bordes, un botón para plegar y desplegar: el
    /// borde de una ventana sin marco no se ve, y nadie lo encuentra solo.
    private func resizeButton(expanded: Bool) -> some View {
        Button {
            store.updateSettings { settings in
                settings.hudSize = expanded ? nil : HUDSize(width: 380, height: 460)
            }
        } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(expanded ? "Plegar" : "Desplegar la caja PC")
    }

    /// Marco de jefe, con el borde del color que lo distinga del combate normal.
    private func bossPanel<Content: View>(
        border: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 5) {
                content()
                if Self.showsMetrics(forHeight: geometry.size.height) {
                    Divider()
                    metricsStrip
                }
                if Self.showsBox(forHeight: geometry.size.height) {
                    Divider()
                    boxSection
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(border.opacity(0.6), lineWidth: 1.5)
                    )
            )
            .contextMenu { hudMenu }
        }
        .padding(4)
    }

    /// Marco propio para la medalla: borde dorado, para que se distinga de un
    /// vistazo de un combate cualquiera.
    private func medalPanel(_ celebration: MedalCelebration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MedalCelebrationView(celebration: celebration, compact: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange, lineWidth: 2)
                )
        )
        .padding(4)
        .contextMenu { hudMenu }
    }

    /// Mismo marco que el combate normal, con la tarjeta de gimnasio dentro.
    private func gymPanel(gym: Gym, battle: ActiveGymBattle) -> some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 5) {
                GymCardView(gym: gym, battle: battle, compact: true)
                if Self.showsMetrics(forHeight: geometry.size.height) {
                    Divider()
                    metricsStrip
                }
                if Self.showsBox(forHeight: geometry.size.height) {
                    Divider()
                    boxSection
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1.5)
                    )
            )
            .contextMenu { hudMenu }
        }
        .padding(4)
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
                    Text(group.displayForm.localizedName + (group.isShiny ? " ✦" : "")
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

}
