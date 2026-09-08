import PokeTokenBarCore
import SwiftUI

/// Zonas de caza: cuáles están abiertas, qué falta para las demás y cuántas
/// especies aporta cada una. Es la respuesta a "¿dónde puedo cazar ahora?".
struct ZonesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let access = store.zoneAccess
        VStack(alignment: .leading, spacing: 5) {
            Text("\(store.unlockedZones.count) de \(store.zoneCatalog.all.count) abiertas · \(store.zoneCatalog.availableSpecies(access).count) especies pueden aparecer")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ForEach(store.zoneCatalog.all) { zone in
                let open = access.opens(zone)
                HStack(spacing: 5) {
                    Image(systemName: open ? "lock.open" : "lock")
                        .font(.system(size: 9))
                        .foregroundStyle(open ? .green : .secondary)
                    Text(zone.name)
                        .font(.system(size: 11, weight: open ? .medium : .regular))
                        .foregroundStyle(open ? .primary : .secondary)
                    Spacer(minLength: 4)
                    if open {
                        Text("\(zone.species.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(zone.unlock.label(kantoOpen: access.kantoOpen))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
