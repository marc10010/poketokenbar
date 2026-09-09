import PokeTokenBarCore
import SwiftUI

/// Combate de liga: el miembro en curso y por dónde va el gauntlet.
struct LeagueCardView: View {
    @EnvironmentObject private var store: GameStore
    let league: League
    let member: LeagueMember
    let run: ActiveLeagueRun
    var compact = false
    /// Hueco a la derecha de la primera fila para el mando de plegar del HUD,
    /// que va encima de la esquina. Solo la fila, no la tarjeta: la barra de HP
    /// aprovecha todo el ancho.
    var headerInset: CGFloat = 0

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
            .padding(.trailing, headerInset)

            BossHPRow(currentHP: run.currentHP, maxHP: run.maxHP, rate: rate, compact: compact)

            if blocked {
                BossBlockedNotice(
                    boss: member,
                    reason: "\(member.name) absorbe \(Fmt.rate(member.absorption)): hace falta ventaja de tipo o una etapa más.",
                    compact: compact
                )
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
            // Solo el barco: la línea antigua decía "esperan a que ganes el
            // Alto Mando" incluso con el Alto Mando ya ganado, porque ahora
            // puede faltar la otra mitad del billete.
            barco

            ForEach(store.leagueCatalog.all) { league in
                row(league)
            }
        }
    }

    /// El barco a la región siguiente: la liga es la mitad del billete y la
    /// Pokédex de la región actual es la otra. Sin decirlo, ganar el Alto Mando
    /// y que no pase nada parecería un bug.
    @ViewBuilder
    private var barco: some View {
        if let transfer = store.transfer(to: "kanto"), !transfer.isOpen {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "ferry")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("El barco a \(transfer.name) · los gimnasios de \(transfer.name) esperan")
                        .font(.system(size: 10, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(transfer.leagueWon
                        ? "\(transfer.league.name) ganado · faltan \(transfer.missingSpecies) especies de \(transfer.from.capitalized) por registrar (\(transfer.registered) de \(transfer.required))"
                        : "Pide ganar \(transfer.league.name) y \(transfer.required) especies de \(transfer.from.capitalized) registradas (tienes \(transfer.registered))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 2)
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
