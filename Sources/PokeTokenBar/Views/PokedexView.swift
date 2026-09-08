import PokeTokenBarCore
import SwiftUI

/// La Pokédex completa: los 251 huecos, tengas lo que tengas. Ocupa el popover
/// entero en vez de vivir en una sección, porque una rejilla de 251 dentro de
/// otra que ya hace scroll no se navega.
struct PokedexView: View {
    @EnvironmentObject private var store: GameStore

    @EnvironmentObject private var sprites: SpriteStore

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 54 * sprites.scale), spacing: 6)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let id = store.selectedDexSpeciesID,
               let entry = store.pokedexEntries.first(where: { $0.species.id == id }) {
                detail(entry)
            } else {
                toolbar
                grid
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if store.selectedDexSpeciesID != nil {
                Button {
                    store.selectedDexSpeciesID = nil
                } label: {
                    Label("Volver a la rejilla", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
            Spacer()
            Text("\(store.pokedexCaptured)/251 · \(store.pokedexSeen) vistos · +\(Fmt.rate(store.collectionBonus)) de daño")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("Nombre o nº", text: Binding(
                    get: { store.pokedexFilter.query },
                    set: { store.pokedexFilter.query = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                if store.pokedexFilter.isActive {
                    Button("Limpiar") { store.pokedexFilter.reset() }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { store.pokedexFilter.generation ?? 0 },
                    set: { store.pokedexFilter.generation = $0 == 0 ? nil : $0 }
                )) {
                    Text("Gen 1 y 2").tag(0)
                    Text("Gen 1").tag(1)
                    Text("Gen 2").tag(2)
                }
                .labelsHidden()
                .frame(width: 100)

                Toggle("Solo los que faltan", isOn: Binding(
                    get: { store.pokedexFilter.onlyMissing },
                    set: { store.pokedexFilter.onlyMissing = $0; if $0 { store.pokedexFilter.onlyCaptured = false } }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(store.filteredPokedexEntries) { entry in
                    cell(entry)
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, Layout.scrollGutter)
        }
        .frame(maxHeight: 420)
    }

    private func cell(_ entry: PokedexEntry) -> some View {
        Button {
            store.selectedDexSpeciesID = entry.species.id
        } label: {
            VStack(spacing: 0) {
                SpriteView(speciesID: entry.species.id, shiny: false, size: 44)
                    .opacity(opacity(entry.state))
                    .grayscale(entry.isCaptured ? 0 : 1)
                Text(entry.state == .unknown ? "#\(String(format: "%03d", entry.species.id))" : entry.species.localizedName)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(entry.isCaptured ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isCaptured ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .help("#\(String(format: "%03d", entry.species.id)) \(entry.species.localizedName) · \(entry.state.label)")
    }

    private func opacity(_ state: PokedexEntry.State) -> Double {
        switch state {
        case .captured: return 1
        case .defeated: return 0.6
        case .unknown: return 0.25
        }
    }

    @ViewBuilder
    private func detail(_ entry: PokedexEntry) -> some View {
        if let group = entry.group {
            ScrollView {
                PokemonDetailView(group: group)
                    .padding(.trailing, Layout.scrollGutter)
            }
        } else {
            unseenDetail(entry)
        }
    }

    /// Ficha de algo que no tienes: sin números tuyos, con lo que sirve para
    /// decidir si te interesa buscarlo.
    private func unseenDetail(_ entry: PokedexEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                AnimatedSpriteView(speciesID: entry.species.id, shiny: false, size: 116)
                    .opacity(opacity(entry.state))
                    .grayscale(1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.species.localizedName).font(.title3.weight(.semibold))
                    Text("#\(String(format: "%03d", entry.species.id)) · Gen \(entry.species.generation)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    TypeChips(types: entry.species.types)
                    HStack(spacing: 5) {
                        RarityBadge(rarity: entry.species.rarity)
                        Text(entry.state.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                row("Veces vencido", Fmt.tokens(entry.defeats))
                row("Aparece con rango", entry.species.requiredRankLabel)
                zonesRow(entry)
                if entry.species.stage > 0, let base = store.pokedex[entry.species.baseFormID] {
                    row("Evoluciona de", base.localizedName)
                }
                if !entry.species.evolvesInto.isEmpty {
                    let names = entry.species.evolvesInto.compactMap { store.pokedex[$0]?.localizedName }
                    row("Evoluciona a", names.joined(separator: ", "))
                }
            }
            Text(hint(entry))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Dónde vive y si esa zona está abierta: es la respuesta a "¿por qué no
    /// me sale?" que antes no estaba en ninguna parte.
    @ViewBuilder
    private func zonesRow(_ entry: PokedexEntry) -> some View {
        let zonas = store.zones(for: entry.species.id)
        if zonas.isEmpty {
            row("Dónde aparece", "sin ruta conocida")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dónde aparece")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(zonas, id: \.zone.id) { entrada in
                    HStack(spacing: 4) {
                        Image(systemName: entrada.open ? "lock.open" : "lock")
                            .font(.system(size: 9))
                            .foregroundStyle(entrada.open ? .green : .secondary)
                        Text(entrada.zone.name)
                            .font(.system(size: 10))
                        if !entrada.open {
                            Text("· \(entrada.zone.unlock.label(kantoOpen: store.zoneAccess.kantoOpen))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func hint(_ entry: PokedexEntry) -> String {
        if entry.species.stage > 0 {
            return "Las formas evolucionadas no aparecen en libertad: consigue su forma base y hazla evolucionar llevándola equipada."
        }
        if store.rank < entry.species.rarity.requiredRank {
            return "Todavía no puede aparecer: hacen falta \(entry.species.rarity.requiredRank.requiredMedals) medallas."
        }
        if !store.isAvailableInTheWild(entry.species.id) {
            return "Sus zonas están cerradas: no puede aparecer hasta que abras alguna."
        }
        return entry.defeats > 0
            ? "Le has ganado \(entry.defeats) veces pero no se quedó. Vuelve a aparecer."
            : "Puede aparecer en cualquier momento."
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.caption.monospaced())
        }
    }
}
