import PokeTokenBarCore
import SwiftUI

/// Combate de liga: el miembro en curso y por dónde va el gauntlet.
struct LeagueCardView: View {
    @EnvironmentObject private var store: GameStore
    let league: League
    let member: LeagueMember
    let run: ActiveLeagueRun
    var compact = false

    private var rate: Double { store.damagePerToken(against: member) }
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
                SpriteView(speciesID: member.signatureSpeciesID, shiny: false, size: compact ? 44 : 62, flipped: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: compact ? 13 : 16, weight: .bold))
                    Text("\(league.name) · \(run.memberIndex + 1) de \(league.members.count)")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                    MatchupBadge(matchup: store.matchup(against: member), compact: compact)
                }
            }

            // Los miembros ya vencidos de esta tirada, para ver el avance.
            HStack(spacing: 3) {
                ForEach(league.members, id: \.order) { other in
                    Circle()
                        .fill(color(for: other))
                        .frame(width: 7, height: 7)
                }
            }

            HPBar(fraction: run.hpFraction, height: compact ? 8 : 12)
            HStack(spacing: 6) {
                Text("\(Fmt.tokens(run.currentHP)) / \(Fmt.tokens(run.maxHP)) HP")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                Spacer(minLength: 0)
                Text(blocked ? "0 HP/token" : "\(Fmt.rate(rate)) HP/token")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(blocked ? Color.red : .secondary)
            }

            if blocked {
                Text("Absorbe \(Fmt.rate(member.absorption)): hace falta ventaja de tipo o una etapa más.")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Abandonar la liga") { store.abandonLeague() }
                .buttonStyle(.link)
                .font(.system(size: compact ? 10 : 11))
                .help("Se reinicia desde el primer miembro: es un gauntlet")
        }
    }

    private func color(for other: LeagueMember) -> Color {
        if other.order <= run.memberIndex { return .green }
        if other.order == run.memberIndex + 1 { return .orange }
        return .secondary.opacity(0.3)
    }
}

/// Las dos ligas: estado, requisito y qué abren.
struct LeaguesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let gate = store.gymGate {
                Text("Los gimnasios de Kanto esperan a que ganes \(gate.name).")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(store.leagueCatalog.all) { league in
                row(league)
            }
        }
    }

    private func row(_ league: League) -> some View {
        let availability = store.availability(of: league)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(league.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(league.place) · \(league.reward.label)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if availability.isAvailable {
                    Button("Retar") { store.startLeague(league.id) }
                        .font(.system(size: 10))
                } else {
                    Text(availability == .won ? "✓ superada" : availability.reason)
                        .font(.system(size: 9))
                        .foregroundStyle(availability == .won ? .green : .secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(league.members, id: \.order) { member in
                    VStack(spacing: 0) {
                        SpriteView(speciesID: member.signatureSpeciesID, shiny: false, size: 26)
                            .opacity(availability == .won ? 1 : 0.55)
                            .grayscale(availability == .won ? 0 : 1)
                        Text(member.name)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
