import PokeTokenBarCore
import SwiftUI

/// Ficha grande de un Pokémon de la caja: sprite a tamaño, tipos, progreso
/// hacia su siguiente forma y sus números. Desde aquí se envía a luchar.
struct PokemonDetailView: View {
    @EnvironmentObject private var store: GameStore
    let group: BoxGroup
    /// En la caja la ficha va fijada encima de la rejilla, que sigue ahí: ahí
    /// el sprite es más pequeño y los números se piden.
    var compact = false
    @State private var showsStats = false

    private var isActive: Bool { store.activeGroupID == group.id }
    private var captured: CapturedPokemon { group.representative }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            header
            Divider()
            progress
            if compact {
                DisclosureGroup(isExpanded: $showsStats) {
                    stats.padding(.top, 3)
                } label: {
                    Text("Sus números")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Divider()
                stats
            }
            branches
            actions
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedSpriteView(speciesID: group.displayForm.id, shiny: group.displaysShiny, size: compact ? 72 : 132)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(group.displayForm.localizedName)
                        .font(.title3.weight(.semibold))
                    if group.isShiny {
                        Text("✦").foregroundStyle(.yellow)
                    }
                }
                Text("#\(String(format: "%03d", group.displayForm.id)) · \(group.displayForm.homeRegion)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                TypeChips(types: group.displayForm.types)
                Text("\(group.stage.label) · \(group.species.rarity.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if group.hasEvolved {
                    Text("Capturado como \(group.species.localizedName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Las ramas y su condición. Sin esto la mecánica es adivinar: la rama la
    /// decide lo último que venció y la hora, y ninguna de las dos cosas se ve
    /// en la ficha por sí sola.
    @ViewBuilder
    private var branches: some View {
        let options = store.branchOptions(for: captured)
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("RAMAS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    if store.activeCanEvolve, let next = options.first(where: \.isNext) {
                        Text("· ahora mismo sería \(next.form.localizedName)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if let next = options.first(where: \.isNext) {
                        Text("· con los tokens que le faltan sería \(next.form.localizedName)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(options) { option in
                    HStack(spacing: 5) {
                        SpriteView(speciesID: option.form.id, shiny: false, size: 22)
                            .grayscale(option.registered ? 0 : 1)
                            .opacity(option.registered ? 1 : 0.55)
                        Text(option.form.localizedName)
                            .font(.system(size: 10, weight: option.isNext ? .semibold : .regular))
                        Text(option.condition.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let region = option.blockedRegion {
                            Text("· necesita \(region)")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if option.registered {
                            Text("✓")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                }
                if let last = store.pokedex[store.state.lastDefeatedSpeciesID ?? 0] {
                    Text("Último vencido: \(last.localizedName) (\(last.displayTypes))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        let earned = captured.tokensEarned
        let remaining = group.stage.tokensToNext(from: earned)
        // Ojo con el orden: una línea que bifurca no tiene "siguiente forma"
        // que anunciar (la decide lo que venzas), pero sí tiene evolución. Sin
        // este caso, un Eevee decía "su línea evolutiva acaba aquí".
        let branches = store.branchOptions(for: captured)
        let blocked = store.blockedRegion(for: captured)
        VStack(alignment: .leading, spacing: 3) {
            if remaining == 0, let blocked, let next = store.branchOptions(for: captured).first(where: \.isNext) ?? nil {
                Text("Listo para evolucionar, pero \(next.form.localizedName) vive en \(blocked): hace falta abrir la región")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if remaining == 0, let blocked, let next = store.nextForm(of: captured) {
                Text("Listo para evolucionar, pero \(next.localizedName) vive en \(blocked): hace falta abrir la región")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if remaining == 0, !branches.isEmpty {
                Text("Listo para evolucionar: lo decide lo próximo que venza")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if let remaining, !branches.isEmpty {
                Text("\(Fmt.tokens(remaining)) de daño para evolucionar")
                    .font(.caption)
                HPBar(fraction: fraction(earned: earned), height: 8)
            } else if let remaining, let next = store.nextForm(of: captured) {
                Text("\(Fmt.tokens(remaining)) de daño para \(next.localizedName)")
                    .font(.caption)
                HPBar(fraction: fraction(earned: earned), height: 8)
            } else if remaining != nil {
                Text("Su línea evolutiva acaba aquí")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Etapa máxima alcanzada")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(Fmt.tokens(earned)) de daño hecho llevándolo equipado")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func fraction(earned: Int) -> Double {
        switch group.stage {
        case .base:
            return Double(earned) / Double(GameRules.stageOneThreshold)
        case .one:
            let span = Double(GameRules.stageTwoThreshold - GameRules.stageOneThreshold)
            return Double(earned - GameRules.stageOneThreshold) / span
        case .two:
            return 1
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 3) {
            // El punto de la rejilla solo tiene color; aquí va con número y
            // nombre, incluido el neutro, que en la rejilla no se pinta.
            if let rival = store.matchupLegendRival,
               let matchup = store.matchupAgainstCurrentTarget(group) {
                row("Contra \(rival)", "\(matchup.badge) \(matchup.label)")
            }
            row("Combates ganados", Fmt.tokens(captured.wildDefeats))
            row("Gimnasios ganados", Fmt.tokens(captured.gymsWon))
            row("Veces vencido en libertad", Fmt.tokens(store.timesDefeated(familyOf: group.species.id)))
            row("Capturado", Fmt.day(captured.capturedAt))
            row("Tu histórico entonces", "\(Fmt.tokens(captured.capturedAtTotalTokens)) tokens")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.caption.monospaced())
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(isActive ? "Ya está luchando" : "Enviar a luchar") {
                store.setActiveCompanion(captured.id)
            }
            .disabled(isActive)

            // El cambio de paleta solo con la versión normal en la caja: si el
            // shiny es el único que tienes, dibujarlo en normal enseñaría un
            // Pokémon que no tienes.
            if store.canToggleShinyDisplay(captured) {
                Button(captured.prefersShiny ? "Ver en normal" : "Ver shiny") {
                    store.toggleShinyDisplay(captured.id)
                }
            } else if group.isShiny {
                Text("✦ Solo lo tienes shiny")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Para verlo con la paleta normal harían falta los dos: el shiny y el normal")
            }

            Spacer(minLength: 0)
            Button("Cerrar") { store.closeDetail() }
                .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.top, 2)
    }
}

/// Ficha del rival salvaje. No es tuyo, así que no tiene tus números: lo útil
/// aquí es a cuánto le pegas y cuántas veces le has ganado ya.
struct RivalDetailView: View {
    @EnvironmentObject private var store: GameStore
    let encounter: WildEncounter
    let species: Pokemon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                AnimatedSpriteView(speciesID: species.id, shiny: encounter.isShiny, size: 132, flipped: true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(species.localizedName).font(.title3.weight(.semibold))
                        if encounter.isShiny { Text("✦").foregroundStyle(.yellow) }
                    }
                    Text("#\(String(format: "%03d", species.id)) · \(species.homeRegion)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    TypeChips(types: species.types)
                    RarityBadge(rarity: encounter.rarity)
                    MatchupBadge(matchup: store.currentMatchup)
                }
            }
            HPBar(fraction: encounter.hpFraction, height: 10)
            Text("\(Fmt.tokens(encounter.currentHP)) / \(Fmt.tokens(encounter.maxHP)) HP")
                .font(.caption.monospaced())
            Text(ownedNotice)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button("Cerrar") { store.closeDetail() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var ownedNotice: String {
        let defeats = store.timesDefeated(familyOf: species.id)
        if store.ownsFamily(of: species.id, shiny: encounter.isShiny) {
            return "Ya tienes esta línea: al vencerlo contará la victoria (\(defeats) hasta ahora) pero no se queda."
        }
        return defeats > 0
            ? "Le has ganado \(defeats) veces. Esta vez sí se queda: te falta en la caja."
            : "Nuevo: al vencerlo entra en la caja."
    }
}
