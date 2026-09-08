import PokeTokenBarCore
import SwiftUI

/// Combate de gimnasio. Sustituye a la tarjeta de rival salvaje mientras hay
/// un líder abierto: no coexisten.
struct GymCardView: View {
    @EnvironmentObject private var store: GameStore
    let gym: Gym
    let battle: ActiveGymBattle
    var compact = false

    private var rate: Double { store.gymDamagePerToken(for: gym) }
    private var blocked: Bool { rate <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 8) {
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

            HPBar(fraction: battle.hpFraction, height: compact ? 8 : 12)
            HStack(spacing: 6) {
                Text("\(Fmt.tokens(battle.currentHP)) / \(Fmt.tokens(battle.maxHP)) HP")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                Spacer(minLength: 0)
                Text(blocked ? "0 HP/token" : "\(Fmt.rate(rate)) HP/token")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(blocked ? .red : .secondary)
            }

            if blocked {
                blockedNotice
            } else if let needed = store.gymTokensNeeded(for: gym, battle: battle) {
                Text("Le quedan \(Fmt.tokens(needed)) tokens tuyos")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Un bloqueo sin salida es un bug de diseño: siempre se dice qué hacer.
    private var blockedNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tu compañero no le hace nada.")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(.red)
            if let best = store.bestCompanion(against: gym) {
                Button {
                    store.setActiveCompanion(best.group.representative.id)
                } label: {
                    Text("Cambiar a \(best.group.displayForm.localizedName) (\(Fmt.rate(best.rate)) HP/token)")
                        .font(.system(size: compact ? 9 : 10))
                }
                .buttonStyle(.link)
            } else {
                Text("Ninguno de tu caja le entra: captura algo de un tipo eficaz.")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Rejilla de las 16 medallas: las conseguidas en color.
struct MedalsView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let earned = Set(store.medalGyms().map(\.id))
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.rank.label)
                    .font(.caption.weight(.semibold))
                if let next = store.rank.next(medals: store.medals) {
                    Text("· \(next.missing) medalla\(next.missing == 1 ? "" : "s") para \(next.rank.label)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(store.gymCatalog.all) { gym in
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
}
