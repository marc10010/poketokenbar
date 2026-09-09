import PokeTokenBarCore
import SwiftUI

/// El líder esperando. Antes el gimnasio se abría solo y te quitaba el salvaje
/// en medio de la partida; ahora es una puerta abierta: dice a quién te
/// enfrentas, a cuánto le pegarías y qué te vas a llevar, y entras tú.
struct GymInvitationCard: View {
    @EnvironmentObject private var store: GameStore
    let gym: Gym

    private var rate: Double { store.damagePerToken(against: gym) }
    private var blocked: Bool { rate <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SpriteView(speciesID: gym.signatureSpeciesID, shiny: false, size: 46, flipped: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(gym.leader)
                            .font(.system(size: 13, weight: .bold))
                        Text("· \(gym.medal)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(gym.city) · absorbe \(Fmt.rate(gym.absorption))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        MatchupBadge(matchup: store.matchup(against: gym), compact: true)
                        Text(blocked ? "0 HP/token" : "\(Fmt.rate(rate)) HP/token")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(blocked ? .red : .secondary)
                    }
                }
                Spacer(minLength: 4)
                Button("Retar") { store.startGym(gym.id) }
                    .font(.system(size: 11))
            }

            if blocked {
                BossBlockedNotice(
                    boss: gym,
                    reason: "\(gym.leader) absorbe \(Fmt.rate(gym.absorption)): con este compañero no le harías nada. Puedes esperar y entrar cuando quieras.",
                    compact: true
                )
            } else {
                Text("Te espera hasta que entres: mientras, sigues cazando.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
