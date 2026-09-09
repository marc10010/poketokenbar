import PokeTokenBarCore
import SwiftUI

struct ActiveCompanionCard: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let companion = store.state.activeCompanion, let form = store.activeForm {
                Button {
                    store.selectedBoxGroupID = store.activeGroupID
                    store.inspectingRival = false
                } label: {
                    SpriteView(speciesID: form.id, shiny: companion.displaysShiny, size: 84)
                }
                .buttonStyle(.plain)
                .help("Ver su ficha")
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(form.localizedName)
                            .font(.title3.weight(.semibold))
                        if companion.isShiny {
                            Text("✦").foregroundStyle(.yellow).help("Shiny")
                        }
                        Text("#\(String(format: "%03d", form.id))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    TypeChips(types: form.types)
                    Text(store.stage.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    EvolutionProgress()
                }
            }
        }
    }
}

struct EvolutionProgress: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        // El progreso es del compañero equipado, no del histórico global.
        let earned = store.activeTokensEarned
        let remaining = store.stage.tokensToNext(from: earned)
        VStack(alignment: .leading, spacing: 3) {
            if let remaining, let next = store.activeNextForm {
                Text("\(Fmt.tokens(remaining)) tokens para \(next.localizedName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HPBar(fraction: stageFraction, height: 5)
                    .frame(width: 180)
            } else if remaining != nil {
                Text("Esta línea evolutiva ya está al final")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Etapa máxima alcanzada")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stageFraction: Double {
        let total = store.activeTokensEarned
        switch store.stage {
        case .base:
            return Double(total) / Double(GameRules.stageOneThreshold)
        case .one:
            let span = Double(GameRules.stageTwoThreshold - GameRules.stageOneThreshold)
            return Double(total - GameRules.stageOneThreshold) / span
        case .two:
            return 1
        }
    }
}

struct EncounterCard: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        SectionCard(title: "Combate") {
            if let encounter = store.state.encounter, let rival = store.rivalSpecies,
               store.inspectingRival {
                RivalDetailView(encounter: encounter, species: rival)
            } else if let encounter = store.state.encounter, let rival = store.rivalSpecies {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        store.inspectingRival = true
                    } label: {
                        SpriteView(speciesID: rival.id, shiny: encounter.isShiny, size: 62, flipped: true)
                    }
                    .buttonStyle(.plain)
                    .help("Ver su ficha")
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(rival.localizedName).font(.body.weight(.semibold))
                            if encounter.isShiny {
                                Text("✦").foregroundStyle(.yellow).help("Shiny")
                            }
                            RarityBadge(rarity: encounter.rarity)
                        }
                        HStack(spacing: 5) {
                            MatchupBadge(matchup: store.currentMatchup)
                            if store.collectionBonus > 0.01 {
                                Text("+\(Fmt.rate(store.collectionBonus)) colección")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.blue)
                                    .help("Cada especie de tu Pokédex suma daño contra salvajes")
                            }
                        }
                        HPBar(fraction: encounter.hpFraction, height: 12)
                        HStack {
                            Text("\(Fmt.tokens(encounter.currentHP)) / \(Fmt.tokens(encounter.maxHP)) HP")
                                .font(.caption.monospaced())
                            Spacer()
                            Text("\(Int((1 - encounter.hpFraction) * 100))%")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Buscando rival…").font(.caption).foregroundStyle(.secondary)
            }

            if let capture = store.lastCapture, let species = store.pokedex[capture.speciesID] {
                Text("Última captura: \(species.localizedName)\(capture.isShiny ? " ✦" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricsView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            metric("Tokens totales", Fmt.tokens(store.totalTokens))
            metric("Este mes", Fmt.tokens(store.monthTokens))
            metric("Daño por token", damageLine)
            metric("Bonus de colección", "+\(Fmt.rate(store.collectionBonus)) por \(store.pokedexCaptured)/251")
            metric("Eventos registrados", Fmt.tokens(store.state.ledger.eventCount))
            metric("Rango", "\(store.rank.label) · \(store.medals)/16 medallas")
            metric("Especies conseguidas", "\(store.speciesCaught) / 251")
            metric("Capturas totales", Fmt.tokens(store.state.box.count))

            let history = store.state.ledger.monthly.sorted { $0.key > $1.key }.prefix(6)
            if history.count > 1 {
                Divider().padding(.vertical, 2)
                ForEach(Array(history), id: \.key) { entry in
                    metric(Fmt.month(entry.key), Fmt.tokens(entry.value))
                }
            }
        }
        .padding(.top, 4)
    }

    /// Contra quién, porque con un jefe abierto no hay salvaje y la tasa del
    /// salvaje es 0: decir "0" mientras el líder recibe daño es mentir.
    private var damageLine: String {
        guard let target = store.currentTarget else { return "sin rival ahora mismo" }
        return "\(Fmt.rate(target.rate)) a \(target.label)"
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced())
        }
    }
}
