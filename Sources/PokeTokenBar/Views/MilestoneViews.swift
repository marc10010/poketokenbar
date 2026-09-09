import PokeTokenBarCore
import SwiftUI

/// Combate contra un legendario. Misma forma que la tarjeta de gimnasio: lo que
/// cambia es que aquí sí se captura, y que se puede abandonar.
struct MilestoneCardView: View {
    @EnvironmentObject private var store: GameStore
    let milestone: Milestone
    let battle: ActiveBossBattle
    var compact = false
    /// Hueco a la derecha de la primera fila para el mando de plegar del HUD,
    /// que va encima de la esquina. Solo la fila, no la tarjeta: la barra de HP
    /// aprovecha todo el ancho.
    var headerInset: CGFloat = 0

    private var rate: Double { store.damagePerToken(against: milestone) }
    private var blocked: Bool { rate <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 8) {
                if let companion = store.state.activeCompanion, let form = store.activeForm {
                    SpriteView(speciesID: form.id, shiny: companion.displaysShiny, size: compact ? 38 : 54)
                    Text("vs")
                        .font(.system(size: compact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                SpriteView(speciesID: milestone.speciesID, shiny: false, size: compact ? 44 : 64, flipped: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(store.pokedex[milestone.speciesID]?.localizedName ?? "Legendario")
                            .font(.system(size: compact ? 13 : 16, weight: .bold))
                        Text("✦")
                            .font(.system(size: compact ? 10 : 12))
                            .foregroundStyle(.purple)
                    }
                    Text("\(milestone.place) · absorbe \(Fmt.rate(milestone.absorption))")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                    MatchupBadge(matchup: store.matchup(against: milestone), compact: compact)
                }
            }
            .padding(.trailing, headerInset)

            HPBar(fraction: battle.hpFraction, height: compact ? 8 : 12)
            HStack(spacing: 6) {
                Text("\(Fmt.tokens(battle.currentHP)) / \(Fmt.tokens(battle.maxHP)) HP")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                Spacer(minLength: 0)
                Text(blocked ? "0 HP/token" : "\(Fmt.rate(rate)) HP/token")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(blocked ? Color.red : .secondary)
            }

            if blocked {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu compañero no le hace nada.")
                        .font(.system(size: compact ? 9 : 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("Un legendario absorbe \(Fmt.rate(milestone.absorption)): hace falta ventaja de tipo o una etapa más.")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Abandonar") { store.abandonMilestone() }
                .buttonStyle(.link)
                .font(.system(size: compact ? 10 : 11))
                .help("Pierdes el progreso de este legendario, pero recuperas tus salvajes")
        }
    }
}

/// Lista de hitos: qué hay disponible, qué falta para el resto y qué ya tienes.
struct MilestonesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(store.state.milestones.defeated.count) de \(store.milestoneCatalog.all.count) legendarios")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ForEach(store.milestoneCatalog.all) { milestone in
                row(milestone)
            }
        }
    }

    private func row(_ milestone: Milestone) -> some View {
        let availability = store.availability(of: milestone)
        let rate = store.damagePerToken(against: milestone)
        return HStack(spacing: 6) {
            SpriteView(speciesID: milestone.speciesID, shiny: false, size: 30)
                .opacity(availability == .defeated ? 1 : (availability.isAvailable ? 0.85 : 0.3))
                .grayscale(availability == .defeated ? 0 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.pokedex[milestone.speciesID]?.localizedName ?? milestone.id)
                    .font(.system(size: 11, weight: .medium))
                Text(milestone.place)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if availability.isAvailable {
                VStack(alignment: .trailing, spacing: 1) {
                    Button("Retar") { store.startMilestone(milestone.id) }
                        .font(.system(size: 10))
                    Text(rate > 0 ? "\(Fmt.rate(rate)) HP/token" : "bloqueado")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(rate > 0 ? .secondary : Color.red)
                }
            } else {
                Text(availability == .defeated ? "✓ conseguido" : availability.reason)
                    .font(.system(size: 9))
                    .foregroundStyle(availability == .defeated ? .green : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
