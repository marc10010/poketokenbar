import PokeTokenBarCore
import SwiftUI

struct BattleDashboardView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showBox = false
    @State private var showMetrics = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActiveCompanionCard()
            Divider()
            EncounterCard()
            Divider()

            DisclosureGroup(isExpanded: $showBox) {
                PCBoxView()
            } label: {
                Label("Caja PC · \(store.speciesCaught)/251", systemImage: "archivebox")
                    .font(.caption.weight(.semibold))
            }

            DisclosureGroup(isExpanded: $showMetrics) {
                MetricsView()
            } label: {
                Label("Consumo", systemImage: "chart.bar")
                    .font(.caption.weight(.semibold))
            }

            Divider()
            FooterView()
        }
        .padding(14)
    }
}

private struct ActiveCompanionCard: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let companion = store.state.activeCompanion, let form = store.activeForm {
                SpriteView(speciesID: form.id, shiny: companion.isShiny, size: 84)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(form.localizedName)
                            .font(.title3.weight(.semibold))
                        if companion.isShiny {
                            Text("✦").foregroundStyle(.yellow).help("Variocolor")
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

private struct EvolutionProgress: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let remaining = store.stage.tokensToNext(from: store.totalTokens)
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
        let total = store.totalTokens
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

private struct EncounterCard: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        SectionCard(title: "Combate") {
            if let encounter = store.state.encounter, let rival = store.rivalSpecies {
                HStack(alignment: .center, spacing: 10) {
                    SpriteView(speciesID: rival.id, shiny: encounter.isShiny, size: 62, flipped: true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(rival.localizedName).font(.body.weight(.semibold))
                            if encounter.isShiny {
                                Text("✦").foregroundStyle(.yellow).help("Variocolor")
                            }
                            RarityBadge(rarity: encounter.rarity)
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

private struct MetricsView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            metric("Tokens totales", Fmt.tokens(store.totalTokens))
            metric("Este mes", Fmt.tokens(store.monthTokens))
            metric("Eventos registrados", Fmt.tokens(store.state.ledger.eventCount))
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

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced())
        }
    }
}
