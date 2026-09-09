import PokeTokenBarCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    private var tab: AppTab {
        AppTab(rawValue: store.selectedTab) ?? .combate
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.state.hasStarter {
                ScrollView { StarterPickerView() }
            } else {
                TabBar()
                Divider().padding(.top, 6)
                if tab.scrollsItself {
                    // Rejillas de cientos de huecos: hacen su propio scroll
                    // para poder fijar la búsqueda y las cabeceras, y para no
                    // anidar dos scrolls en el mismo eje.
                    content
                        .padding(14)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    // Acotado y con scroll: una ficha abierta pasa de 1000 pt y
                    // no cabría en la pantalla de un portátil.
                    ScrollView(.vertical) {
                        content
                            .padding(14)
                            .padding(.trailing, Layout.scrollGutter)
                    }
                }
            }
        }
        .frame(width: 370 + Layout.scrollGutter)
        // Fija, no máxima: el popover mide 620 y las pestañas que hacen su
        // propio scroll necesitan saber cuánto sitio tienen.
        .frame(height: 620)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .combate: CombatTabView()
        case .progreso: ProgressTabView()
        case .caja: BoxTabView()
        case .pokedex: PokedexView()
        case .ajustes: SettingsTabView()
        }
    }
}

/// Combate: compañero, rival o jefe, y las cifras del momento.
struct CombatTabView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let region = store.lastRegion {
                RegionCelebrationView(transfer: region)
                Divider()
            }
            if let celebration = store.lastMedal {
                MedalCelebrationView(celebration: celebration)
                Divider()
            }

            ActiveCompanionCard()
            Divider()

            if let active = store.activeLeague {
                SectionCard(title: active.league.name) {
                    LeagueCardView(league: active.league, member: active.member, run: active.run)
                }
            } else if let active = store.activeMilestone {
                SectionCard(title: "Hito legendario") {
                    MilestoneCardView(milestone: active.milestone, battle: active.battle)
                }
            } else if let active = store.activeGym {
                SectionCard(title: "Gimnasio") {
                    GymCardView(gym: active.gym, battle: active.battle)
                }
            } else {
                EncounterCard()
            }

            Divider()
            SectionCard(title: "Consumo", collapsible: true) {
                MetricsView()
            }
        }
    }
}

/// Progreso: la escalera de desbloqueo, y debajo el detalle de cada sistema.
struct ProgressTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCard(title: "Rango", collapsible: true) {
                MedalsView()
            }
            Divider()
            SectionCard(title: "Ligas", collapsible: true) {
                LeaguesView()
            }
            Divider()
            SectionCard(title: "Legendarios", collapsible: true) {
                MilestonesView()
            }
            Divider()
            SectionCard(title: "Zonas", collapsible: true) {
                ZonesView()
            }
            Divider()
            SectionCard(title: "Escalera de desbloqueo", collapsible: true) {
                LadderView()
            }
        }
    }
}

/// Caja: ficha fijada y rejilla, las dos a la vez.
struct BoxTabView: View {
    var body: some View {
        PCBoxView()
    }
}

/// Ajustes: fuentes de tokens, sprites, HUD y reinicio.
struct SettingsTabView: View {
    var body: some View {
        FooterView()
    }
}
