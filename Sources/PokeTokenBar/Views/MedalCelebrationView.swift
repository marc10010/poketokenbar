import PokeTokenBarCore
import SwiftUI

/// Se come el HUD durante unos segundos al ganar una medalla. Es el único hito
/// del juego, y hasta ahora lo único que cambiaba era un contador.
struct MedalCelebrationView: View {
    @EnvironmentObject private var store: GameStore
    let celebration: MedalCelebration
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.22))
                        .frame(width: compact ? 54 : 72, height: compact ? 54 : 72)
                    SpriteView(speciesID: celebration.gym.signatureSpeciesID, shiny: false, size: compact ? 44 : 60, flipped: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("¡\(celebration.gym.medal)!")
                        .font(.system(size: compact ? 14 : 17, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Has vencido a \(celebration.gym.leader) · \(celebration.gym.city)")
                        .font(.system(size: compact ? 10 : 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(celebration.medals) de 16 medallas")
                        .font(.system(size: compact ? 10 : 11, design: .monospaced))
                }
            }

            if let rank = celebration.newRank {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rango \(rank.label)")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    if celebration.unlocked.isEmpty {
                        Text("No quedan tiers por desbloquear")
                            .font(.system(size: compact ? 9 : 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ya aparecen: \(celebration.unlocked.map(\.label).joined(separator: ", "))")
                            .font(.system(size: compact ? 9 : 11))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let next = store.rank.next(medals: celebration.medals) {
                Text("\(next.missing) más para \(next.rank.label)")
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.secondary)
            }

            Button("Seguir") { store.dismissMedalCelebration() }
                .buttonStyle(.link)
                .font(.system(size: compact ? 10 : 12))
        }
    }
}
