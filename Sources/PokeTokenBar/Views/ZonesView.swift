import PokeTokenBarCore
import SwiftUI

/// Zonas de caza: cuáles están abiertas, qué falta para las demás, y cuál está
/// enfocada. Es la respuesta a "¿dónde puedo cazar ahora?" y a "¿cómo consigo
/// **este** que me falta?".
struct ZonesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let access = store.zoneAccess
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.unlockedZones.count) de \(store.zoneCatalog.all.count) abiertas · \(store.zoneCatalog.availableSpecies(access).count) especies pueden aparecer")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let focused = store.focusedZone {
                let summary = store.focusSummary(focused)
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Cazando en \(focused.name)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    Button("Quitar") { store.focus(zoneID: nil) }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
                Text("Sale cualquiera de sus \(summary.pool) especies, a partes iguales\(summary.missing > 0 ? " · te faltan \(summary.missing) por capturar" : " · ya las tienes todas")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sin zona enfocada: el rival sale del bombo de todas las abiertas.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 1)

            // En orden de desbloqueo: es el orden en que aparecen y por tanto
            // el que se quiere leer, no el del fichero de datos.
            ForEach(store.zoneCatalog.inUnlockOrder) { zone in
                row(zone, open: access.opens(zone))
            }
        }
    }

    @ViewBuilder
    private func row(_ zone: Zone, open: Bool) -> some View {
        let focused = store.focusedZone?.id == zone.id
        let summary = open ? store.focusSummary(zone) : (pool: 0, missing: 0)
        HStack(spacing: 5) {
            Image(systemName: focused ? "scope" : (open ? "lock.open" : "lock"))
                .font(.system(size: 9))
                .foregroundStyle(focused ? .orange : (open ? .green : .secondary))
            Text(zone.name)
                .font(.system(size: 11, weight: focused ? .semibold : (open ? .medium : .regular)))
                .foregroundStyle(open ? .primary : .secondary)
            Spacer(minLength: 4)
            if open {
                // Con la palabra delante: "41 de 45" no dice si son las que
                // tienes o las que te faltan, y hay que preguntarlo.
                Text(summary.missing > 0 ? "faltan \(summary.missing) de \(summary.pool)" : "las \(summary.pool) ✓")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(summary.missing > 0 ? .primary : .secondary)
                    .help(summary.missing > 0
                        ? "Te faltan \(summary.missing) de las \(summary.pool) especies que salen aquí"
                        : "Ya tienes las \(summary.pool) que salen aquí")
                if summary.pool > 0 {
                    Button(focused ? "Quitar" : "Cazar aquí") {
                        store.focus(zoneID: focused ? nil : zone.id)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 9))
                }
            } else {
                Text(zone.unlock.label(kantoOpen: store.zoneAccess.kantoOpen))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
