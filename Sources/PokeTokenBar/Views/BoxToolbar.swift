import PokeTokenBarCore
import SwiftUI

/// Búsqueda y filtros de la caja PC. Aparece encima de la rejilla porque a
/// partir de unas decenas de huecos el scroll deja de servir para encontrar
/// algo concreto.
struct BoxToolbar: View {
    @EnvironmentObject private var store: GameStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    TextField(
                        compact ? "Buscar" : "Nombre o nº de Pokédex",
                        text: Binding(
                            get: { store.boxFilter.query },
                            set: { store.boxFilter.query = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    if !store.boxFilter.query.isEmpty {
                        Button {
                            store.boxFilter.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                filterMenu
            }

            HStack(spacing: 5) {
                Text(countLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if store.boxFilter.isActive {
                    Button("Limpiar") { store.boxFilter.reset() }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
                Spacer(minLength: 0)
            }

            if !store.boxFilter.activeSummary.isEmpty, !compact {
                Text(store.boxFilter.activeSummary.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var countLabel: String {
        let shown = store.filteredBoxGroups.count
        let total = store.boxGroups.count
        let species = store.speciesCaught
        if store.boxFilter.isActive {
            return "\(shown) de \(total) huecos"
        }
        return "\(total) huecos · \(species)/251 especies · \(Fmt.tokens(store.state.box.count)) capturas"
    }

    private var filterMenu: some View {
        Menu {
            Picker("Ordenar por", selection: Binding(
                get: { store.boxFilter.sort },
                set: { store.boxFilter.sort = $0 }
            )) {
                ForEach(BoxFilter.Sort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }

            Divider()

            Toggle("Solo shiny", isOn: binding(\.onlyShiny))
            Toggle("Solo evolucionados", isOn: binding(\.onlyEvolved))
            Toggle("Solo repetidos", isOn: binding(\.onlyDuplicates))

            Divider()

            Picker("Generación", selection: Binding(
                get: { store.boxFilter.generation ?? 0 },
                set: { store.boxFilter.generation = $0 == 0 ? nil : $0 }
            )) {
                Text("Las dos").tag(0)
                Text("Gen 1").tag(1)
                Text("Gen 2").tag(2)
            }

            Divider()

            // Solo los tipos que tienes: ofrecer los 18 siempre sería ruido.
            Menu("Tipo") {
                ForEach(store.typesInBox, id: \.self) { type in
                    Toggle(TypeStyle.label(type), isOn: Binding(
                        get: { store.boxFilter.types.contains(type) },
                        set: { isOn in
                            if isOn {
                                store.boxFilter.types.insert(type)
                            } else {
                                store.boxFilter.types.remove(type)
                            }
                        }
                    ))
                }
            }

            if store.boxFilter.isActive {
                Divider()
                Button("Limpiar filtros") { store.boxFilter.reset() }
            }
        } label: {
            Image(systemName: store.boxFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .help("Filtros y orden")
    }

    private func binding(_ path: WritableKeyPath<BoxFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.boxFilter[keyPath: path] },
            set: { store.boxFilter[keyPath: path] = $0 }
        )
    }
}
