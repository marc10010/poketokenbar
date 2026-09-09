import PokeTokenBarCore
import SwiftUI

/// Ficha de un gimnasio, con el mismo papel que la de un Pokémon: aquí se ve
/// contra qué vas y con quién conviene ir, que es la decisión del juego.
struct GymDetailView: View {
    @EnvironmentObject private var store: GameStore
    let gym: Gym

    private var won: Bool { store.hasMedal(gym.id) }
    private var isNext: Bool { store.nextGym?.id == gym.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            status
            Divider()
            matchup
            Button("Cerrar") { store.selectedGymID = nil }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedSpriteView(speciesID: gym.signatureSpeciesID, shiny: false, size: 116, flipped: true)
                .opacity(won || isNext ? 1 : 0.45)
                .grayscale(won || isNext ? 0 : 0.8)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(gym.order). \(gym.leader)")
                    .font(.title3.weight(.semibold))
                Text("\(gym.city) · \(gym.region.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(gym.medal)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(won ? .orange : .secondary)
                if let star = store.pokedex[gym.signatureSpeciesID] {
                    TypeChips(types: star.types)
                    Text(star.localizedName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("Estado", won ? "Medalla conseguida" : (isNext ? "El siguiente" : "Aún por llegar"))
            row("HP", "\(Fmt.tokens(gym.hpRange.lowerBound)) – \(Fmt.tokens(gym.hpRange.upperBound))")
            row("Absorbe", "\(Fmt.rate(gym.absorption)) por token")
            if isNext, store.activeGym == nil {
                let left = store.gymTriggerProgress
                row("Se abre en", "\(Fmt.tokens(left.tokensLeft)) tokens o \(left.capturesLeft) victorias")
            }
        }
    }

    @ViewBuilder
    private var matchup: some View {
        let rate = store.damagePerToken(against: gym)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Tu compañero")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                MatchupBadge(matchup: store.matchup(against: gym))
                Text(rate > 0 ? "\(Fmt.rate(rate)) HP/token" : "0 HP/token")
                    .font(.caption.monospaced())
                    .foregroundStyle(rate > 0 ? Color.primary : Color.red)
            }
            if let best = store.bestCompanion(against: gym), best.rate > rate {
                Button {
                    store.setActiveCompanion(best.group.representative.id)
                } label: {
                    Text("Mejor con \(best.group.displayForm.localizedName) (\(Fmt.rate(best.rate)) HP/token)")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.caption.monospaced())
        }
    }
}
