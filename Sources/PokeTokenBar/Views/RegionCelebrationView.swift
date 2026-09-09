import PokeTokenBarCore
import SwiftUI

/// Abrir una región es el hito más grande del juego y hasta ahora no se veía:
/// ganabas el Alto Mando y el gimnasio siguiente aparecía en silencio. Mismo
/// marco que la celebración de medalla, con lo que se abre.
struct RegionCelebrationView: View {
    @EnvironmentObject private var store: GameStore
    let transfer: GameStore.RegionTransfer

    private var zones: [Zone] {
        store.zoneCatalog.all.filter { $0.unlock.requiresKanto || $0.region == transfer.region }
    }

    private var gyms: [Gym] { store.gymCatalog.gyms(in: transfer.region) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SpriteView(speciesID: gyms.first?.signatureSpeciesID ?? 25, shiny: false, size: 56)
                .background(Circle().fill(Color.blue.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text("¡\(transfer.name) abierta!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
                Text("Ganaste \(transfer.league.name) y registraste \(transfer.registered) especies de \(transfer.from.capitalized)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(gyms.count) gimnasios · \(zones.count) zonas nuevas")
                    .font(.system(size: 11, design: .monospaced))
                Button("Seguir") { store.dismissRegionCelebration() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}
