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
                // Acotado y con scroll: una ficha abierta pasa de 1000 pt y no
                // cabría en la pantalla de un portátil.
                ScrollView(.vertical) {
                    content
                        .padding(14)
                        .padding(.trailing, Layout.scrollGutter)
                }
            }
        }
        .frame(width: 370 + Layout.scrollGutter)
        .frame(maxHeight: 620)
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
            MetricsView()
        }
    }
}

/// Progreso: la escalera de desbloqueo, y debajo el detalle de cada sistema.
struct ProgressTabView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showLadder = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCard(title: "Rango") {
                MedalsView()
            }
            Divider()
            SectionCard(title: "Ligas") {
                LeaguesView()
            }
            Divider()
            SectionCard(title: "Legendarios") {
                MilestonesView()
            }
            Divider()
            SectionCard(title: "Zonas") {
                ZonesView()
            }
            Divider()
            DisclosureGroup(isExpanded: $showLadder) {
                LadderView().padding(.top, 4)
            } label: {
                Label("Escalera de desbloqueo", systemImage: "list.number")
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

/// Caja: la ficha si hay una abierta, la rejilla si no.
struct BoxTabView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected = store.selectedBoxGroupID,
               let group = store.boxGroups.first(where: { $0.id == selected }) {
                PokemonDetailView(group: group)
            } else {
                PCBoxView()
            }
        }
    }
}

/// Ajustes: fuentes de tokens, sprites, HUD y reinicio.
struct SettingsTabView: View {
    var body: some View {
        FooterView()
    }
}
