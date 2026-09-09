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
            } else if let active = store.activeLeague {
                bossPanel(border: .yellow) {
                    LeagueCardView(
                        league: active.league,
                        member: active.member,
                        run: active.run,
                        compact: true
                    )
                }
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
                // Compacta: en un panel de 200 pt la ficha entera no cabe, y
                // aquí sí sustituye a la rejilla porque no hay sitio para las dos.
                PokemonDetailView(group: group, compact: true)
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
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 5) {
                        battleHeader(
                            encounter: encounter,
                            rival: rival,
                            companion: companion,
                            form: form,
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
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    resizeHandle(expanded: showsMetrics || showsBox)
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
            metric("Daño por token", "\(Fmt.rate(store.wildDamagePerToken)) · \(store.currentMatchup.label)")
            metric("Bonus de colección", "+\(Fmt.rate(store.collectionBonus)) · \(store.pokedexCaptured)/251")
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

    /// Dónde cabe la ficha que pide un clic en un sprite.
    enum DetailTarget: Equatable {
        /// En el propio panel, que ya está desplegado.
        case hud
        /// En el popover: el panel no se agranda solo, eso lo decide el botón.
        case popover
    }

    static func detailTarget(forHeight height: CGFloat) -> DetailTarget {
        showsBox(forHeight: height) ? .hud : .popover
    }

    /// Abre la ficha donde haya sitio. El panel no crece por un clic: crecer
    /// es cosa del botón de la esquina.
    private func openDetail(rival: Bool, panelHeight: CGFloat) {
        store.inspectingRival = rival
        store.selectedBoxGroupID = rival ? nil : store.activeGroupID
        guard Self.detailTarget(forHeight: panelHeight) == .popover else { return }
        store.selectedTab = rival ? "combate" : "caja"
        NotificationCenter.default.post(name: .poketokenbarShowPopover, object: nil)
    }

    private func detailHelp(_ name: String, panelHeight: CGFloat) -> String {
        Self.detailTarget(forHeight: panelHeight) == .hud
            ? "Ver la ficha de \(name)"
            : "Abrir la ficha de \(name) (el panel no se agranda solo: usa el botón de la esquina)"
    }

    private func battleHeader(
        encounter: WildEncounter,
        rival: Pokemon,
        companion: CapturedPokemon,
        form: Pokemon,
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
                .help(detailHelp(form.localizedName, panelHeight: panelHeight))
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
                .help(detailHelp(rival.localizedName, panelHeight: panelHeight))
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
            }
            HPBar(fraction: encounter.hpFraction, height: 8)
            Text("\(Fmt.tokens(encounter.currentHP)) / \(Fmt.tokens(encounter.maxHP)) HP")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func expandedFor(height: CGFloat) -> Bool {
        Self.showsMetrics(forHeight: height) || Self.showsBox(forHeight: height)
    }

    /// El mando de plegar y desplegar: una columna en el borde derecho, a lo
    /// alto del panel y en el mismo sitio en los cuatro. Antes era un icono
    /// dentro de la cabecera del combate salvaje, así que en los paneles de
    /// jefe no había ninguno y en el compacto competía por el ancho con el
    /// nombre del rival.
    private func resizeHandle(expanded: Bool) -> some View {
        Button {
            if expanded {
                store.collapseHUD()
            } else {
                store.updateSettings { $0.hudSize = HUDSize(width: 380, height: 460) }
            }
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .overlay(
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                )
        }
        .buttonStyle(.plain)
        .help(expanded ? "Plegar y cerrar la caja PC" : "Desplegar: métricas y caja PC")
    }

    /// Marco de jefe, con el borde del color que lo distinga del combate normal.
    private func bossPanel<Content: View>(
        border: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 6) {
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                resizeHandle(expanded: expandedFor(height: geometry.size.height))
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
            HStack(alignment: .top, spacing: 6) {
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                resizeHandle(expanded: expandedFor(height: geometry.size.height))
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
        // Sin lista de Pokémon: enumeraba los últimos 8 en el menú y con la
        // caja llena eso ni cabe ni se busca. La caja tiene búsqueda, filtros,
        // tramos y teclado; el menú solo tiene que llevar hasta ella.
        if store.boxGroups.count > 1 {
            Button("Cambiar de compañero en la caja PC (\(store.speciesCaught)/251)…") {
                store.selectedTab = "caja"
                store.selectedBoxGroupID = store.activeGroupID
                NotificationCenter.default.post(name: .poketokenbarShowPopover, object: nil)
            }
            Divider()
        }

        if store.state.settings.hudSize == nil {
            Button("Desplegar el HUD (métricas y caja PC)") {
                store.updateSettings { $0.hudSize = HUDSize(width: 380, height: 460) }
            }
        } else {
            Button("Plegar el HUD (cerrar la caja PC)") { store.collapseHUD() }
        }

        if store.state.settings.hudFreeOrigin != nil {
            Button("Volver a la esquina") {
                store.updateSettings { $0.hudFreeOrigin = nil }
            }
        }
        Button(store.state.settings.hudLocked ? "Desbloquear (poder moverlo)" : "Bloquear en su sitio") {
            store.updateSettings { $0.hudLocked.toggle() }
        }
        // Con el nombre del sitio del que vuelve: este menú vive en el HUD, así
        // que ocultarlo deja la única forma de recuperarlo en otra pantalla.
        Button("Ocultar el HUD (vuelve desde Ajustes)") {
            store.updateSettings { $0.hudEnabled = false }
        }
        Divider()
        Button("Salir de PokeTokenBar") { NSApplication.shared.terminate(nil) }
    }

}
