import PokeTokenBarCore
import SwiftUI

/// Ficha grande de un Pokémon de la caja: sprite a tamaño, tipos, progreso
/// hacia su siguiente forma y sus números. Desde aquí se envía a luchar.
struct PokemonDetailView: View {
    @EnvironmentObject private var store: GameStore
    let group: BoxGroup

    private var isActive: Bool { store.activeGroupID == group.id }
    private var captured: CapturedPokemon { group.representative }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            progress
            Divider()
            stats
            actions
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SpriteView(speciesID: group.displayForm.id, shiny: group.displaysShiny, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(group.displayForm.localizedName)
                        .font(.title3.weight(.semibold))
                    if group.isShiny {
                        Text("✦").foregroundStyle(.yellow)
                    }
                }
                Text("#\(String(format: "%03d", group.displayForm.id)) · Gen \(group.displayForm.generation)")
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

    @ViewBuilder
    private var progress: some View {
        let earned = captured.tokensEarned
        let remaining = group.stage.tokensToNext(from: earned)
        VStack(alignment: .leading, spacing: 3) {
            if let remaining, let next = store.nextForm(of: captured) {
                Text("\(Fmt.tokens(remaining)) tokens para \(next.localizedName)")
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
            Text("\(Fmt.tokens(earned)) tokens ganados llevándolo equipado")
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
            row("Combates ganados", Fmt.tokens(captured.wildDefeats))
            row("Gimnasios ganados", Fmt.tokens(captured.gymsWon))
            row("Veces vencido en libertad", Fmt.tokens(store.timesDefeated(familyOf: group.species.id)))
            row("En la caja", Fmt.tokens(group.count))
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

            if group.isShiny {
                Button(captured.prefersShiny ? "Ver en normal" : "Ver variocolor") {
                    store.toggleShinyDisplay(captured.id)
                }
            }

            Spacer(minLength: 0)
            Button("Cerrar") { store.selectedBoxGroupID = nil }
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
                SpriteView(speciesID: species.id, shiny: encounter.isShiny, size: 96, flipped: true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(species.localizedName).font(.title3.weight(.semibold))
                        if encounter.isShiny { Text("✦").foregroundStyle(.yellow) }
                    }
                    Text("#\(String(format: "%03d", species.id)) · Gen \(species.generation)")
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
            Button("Cerrar") { store.inspectingRival = false }
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
