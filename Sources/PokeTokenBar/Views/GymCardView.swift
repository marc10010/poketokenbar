import PokeTokenBarCore
import SwiftUI

/// Combate de gimnasio. Sustituye a la tarjeta de rival salvaje mientras hay
/// un líder abierto: no coexisten.
struct GymCardView: View {
    @EnvironmentObject private var store: GameStore
    let gym: Gym
    let battle: ActiveGymBattle
    var compact = false
    /// Hueco a la derecha de la primera fila para el mando de plegar del HUD,
    /// que va encima de la esquina. Solo la fila, no la tarjeta: la barra de HP
    /// aprovecha todo el ancho.
    var headerInset: CGFloat = 0

    private var rate: Double { store.damagePerToken(against: gym) }
    private var blocked: Bool { rate <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 8) {
                // El compañero también: hasta ahora se veía contra qué vas,
                // pero no con quién.
                if let companion = store.state.activeCompanion, let form = store.activeForm {
                    SpriteView(speciesID: form.id, shiny: companion.displaysShiny, size: compact ? 38 : 54)
                    Text("vs")
                        .font(.system(size: compact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                SpriteView(speciesID: gym.signatureSpeciesID, shiny: false, size: compact ? 42 : 62, flipped: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(gym.leader)
                            .font(.system(size: compact ? 13 : 15, weight: .bold))
                        Text("· \(gym.medal)")
                            .font(.system(size: compact ? 9 : 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(gym.city) · absorbe \(Fmt.rate(gym.absorption))")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                    MatchupBadge(matchup: store.matchup(against: gym), compact: compact)
                }
            }
            .padding(.trailing, headerInset)

            BossHPRow(currentHP: battle.currentHP, maxHP: battle.maxHP, rate: rate, compact: compact)

            if blocked {
                BossBlockedNotice(
                    boss: gym,
                    reason: "\(gym.leader) absorbe \(Fmt.rate(gym.absorption)): hace falta ventaja de tipo o una etapa más.",
                    compact: compact
                )
            } else if let needed = store.gymTokensNeeded(for: gym, battle: battle) {
                Text("Le quedan \(Fmt.tokens(needed)) tokens tuyos")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
            }

            Button("Salir del gimnasio") { store.abandonGym() }
                .buttonStyle(.link)
                .font(.system(size: compact ? 10 : 11))
                .help("Pierdes el progreso contra el líder, pero recuperas tus salvajes y puedes volver cuando quieras")
        }
    }

}

/// Rejilla de las 16 medallas: las conseguidas en color.
struct MedalsView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(store.rank.label)
                    .font(.caption.weight(.semibold))
                Text("· \(store.medals) de \(store.gymCatalog.count) medallas en total")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let next = store.rank.next(medals: store.medals) {
                Text("\(next.missing) más para \(next.rank.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Una fila por región con su propio contador: el total de 16 no
            // dice en qué región estás, y las ocho de Kanto ni se pueden
            // intentar hasta ganar el Alto Mando de Johto.
            ForEach(store.medalsByRegion) { region in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(region.name.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(region.open ? .primary : .secondary)
                            .tracking(0.5)
                        Text("\(region.earned)/\(region.total)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let gate = region.gate {
                            Text("· cerrada hasta ganar \(gate.name)")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    medals(of: region.region)
                }
            }
        }
    }

    private func medals(of region: String) -> some View {
        let earned = Set(store.medalGyms().map(\.id))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(store.gymCatalog.gyms(in: region)) { gym in
                let won = earned.contains(gym.id)
                let isNext = store.nextGym?.id == gym.id
                Button {
                    store.selectedGymID = gym.id
                } label: {
                    SpriteView(speciesID: gym.signatureSpeciesID, shiny: false, size: 30)
                        .opacity(won ? 1 : (isNext ? 0.75 : 0.18))
                        .grayscale(won ? 0 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isNext ? Color.orange.opacity(0.22) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    store.lastMedal?.gym.id == gym.id ? Color.orange : .clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .onRightClick { store.selectedGymID = gym.id }
                .help("\(gym.medal) · \(gym.leader) (\(gym.city))\(won ? " ✓" : "")\(isNext ? " · el siguiente" : "")")
            }
        }
    }
}
