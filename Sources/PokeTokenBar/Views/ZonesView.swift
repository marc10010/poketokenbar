import PokeTokenBarCore
import SwiftUI

/// Zonas de caza: dónde estás, cuáles están abiertas y qué falta para las
/// demás. Es la respuesta a "¿dónde estoy cazando?" y a "¿cómo consigo **este**
/// que me falta?".
struct ZonesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let access = store.zoneAccess
        let here = store.currentZone
        let summary = store.zoneSummary(here)
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.unlockedZones.count) de \(store.zoneCatalog.all.count) abiertas · \(store.zoneCatalog.availableSpecies(access).count) especies pueden aparecer")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Estás en \(here.name)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(Fmt.tokens(store.zoneHP(here))) HP")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Lo que aguanta cada salvaje de aquí. Sube con la profundidad de la zona.")
            }
            Text(currentLine(summary))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 1)

            // En orden de desbloqueo: es el orden en que aparecen, el que dice
            // cuánto pega cada una, y por tanto el que se quiere leer.
            ForEach(store.zoneCatalog.inUnlockOrder) { zone in
                row(zone, open: access.opens(zone), here: zone.id == here.id)
            }
        }
    }

    /// Con una sola especie las plurales cantan: "Salen sus 1 especies".
    private func currentLine(_ summary: (pool: Int, missing: Int)) -> String {
        let sale = summary.pool == 1
            ? "Sale su única especie"
            : "Salen sus \(summary.pool) especies, las raras menos a menudo"
        let falta: String
        switch summary.missing {
        case 0: falta = "ya las tienes todas"
        case 1: falta = "te falta 1 por capturar"
        default: falta = "te faltan \(summary.missing) por capturar"
        }
        return "\(sale) · \(falta)"
    }

    @ViewBuilder
    private func row(_ zone: Zone, open: Bool, here: Bool) -> some View {
        let summary = open ? store.zoneSummary(zone) : (pool: 0, missing: 0)
        HStack(spacing: 5) {
            Image(systemName: here ? "figure.walk" : (open ? "lock.open" : "lock"))
                .font(.system(size: 9))
                .foregroundStyle(here ? .orange : (open ? .green : .secondary))
            Text(zone.name)
                .font(.system(size: 11, weight: here ? .semibold : (open ? .medium : .regular)))
                .foregroundStyle(open ? .primary : .secondary)
            Text("\(Fmt.compact(store.zoneHP(zone))) HP")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Vida de sus salvajes · zona \(store.zoneDepth(zone)) de \(store.zoneCatalog.all.count)")
            Spacer(minLength: 4)
            if open {
                // Con la palabra delante: "41 de 45" no dice si son las que
                // tienes o las que te faltan, y hay que preguntarlo.
                Text(summary.missing > 0 ? "falta\(summary.missing == 1 ? "" : "n") \(summary.missing) de \(summary.pool)" : "las \(summary.pool) ✓")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(summary.missing > 0 ? .primary : .secondary)
                    .help(summary.missing > 0
                        ? "Te faltan \(summary.missing) de las \(summary.pool) especies que salen aquí"
                        : "Ya tienes las \(summary.pool) que salen aquí")
                if summary.pool > 0, !here {
                    Button("Ir") { store.move(toZone: zone.id) }
                        .buttonStyle(.link)
                        .font(.system(size: 9))
                }
            } else {
                Text(zone.unlock.label(openRegions: store.openRegions))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
