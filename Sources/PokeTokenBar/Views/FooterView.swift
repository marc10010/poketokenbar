import PokeTokenBarCore
import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var sources: TokenSourceCoordinator
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources.descriptions, id: \.name) { source in
                HStack(spacing: 5) {
                    Circle()
                        .fill(source.healthy ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(source.name).font(.system(size: 10, weight: .medium))
                    Text(source.status).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { store.state.settings.countCacheTokens },
                set: { newValue in store.updateSettings { $0.countCacheTokens = newValue } }
            )) {
                Text("Contar tokens de caché como daño").font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { store.state.settings.typeEffectivenessEnabled },
                set: { newValue in store.updateSettings { $0.typeEffectivenessEnabled = newValue } }
            )) {
                Text("Efectividad por tipos (agua > fuego…)").font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { store.state.settings.hudEnabled },
                set: { newValue in store.updateSettings { $0.hudEnabled = newValue } }
            )) {
                Text("HUD flotante en una esquina").font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            if store.state.settings.hudEnabled {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { store.state.settings.hudCorner },
                        set: { newValue in store.updateSettings { $0.hudCorner = newValue } }
                    )) {
                        ForEach(HUDCorner.allCases, id: \.self) { corner in
                            Text(corner.label).tag(corner)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 118)

                    Slider(
                        value: Binding(
                            get: { store.state.settings.hudOpacity },
                            set: { newValue in store.updateSettings { $0.hudOpacity = newValue } }
                        ),
                        in: 0.25...1
                    )
                    .frame(width: 90)
                    .help("Opacidad del HUD")
                }
                .font(.system(size: 10))

                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { store.state.settings.hudLocked },
                        set: { newValue in store.updateSettings { $0.hudLocked = newValue } }
                    )) {
                        Text("Bloqueado (no se puede mover ni recibe clics)").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox)

                    if store.state.settings.hudFreeOrigin != nil {
                        Button("Volver a la esquina") {
                            store.updateSettings { $0.hudFreeOrigin = nil }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    }
                }
            }

            HStack {
                Button("Reiniciar partida…") { confirmingReset = true }
                    .alert("¿Empezar de cero?", isPresented: $confirmingReset) {
                        Button("Reiniciar", role: .destructive) { store.resetGame() }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Se borran la caja, las medallas, las estadísticas y el histórico de tokens. Los ajustes se mantienen. No hay vuelta atrás.")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
            }

            HStack {
                Button("Salir") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Text("1 token = 1 HP").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}
