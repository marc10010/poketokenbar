import PokeTokenBarCore
import SwiftUI

/// Las cifras de consumo, en un solo sitio.
///
/// Estaban escritas dos veces —una en el popover y otra en el HUD— con las
/// mismas ocho filas y etiquetas ligeramente distintas. No es teoría: el fallo
/// de "0 al salvaje" con un jefe abierto hubo que arreglarlo en las dos, y las
/// listas ya habían divergido (una decía "Especies" y la otra "Especies
/// conseguidas").
struct MetricsList: View {
    @EnvironmentObject private var store: GameStore

    enum Style {
        case popover
        case hud

        var fontSize: CGFloat { self == .hud ? 11 : 12 }
    }

    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: style == .hud ? 2 : 6) {
            ForEach(rows, id: \.label) { row in
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: style.fontSize))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(row.value)
                        .font(.system(size: style.fontSize, weight: style == .hud ? .medium : .regular, design: .monospaced))
                }
            }
        }
    }

    private struct Row {
        let label: String
        let value: String
    }

    private var rows: [Row] {
        var rows = [
            Row(label: "Tokens totales", value: Fmt.tokens(store.totalTokens)),
            Row(label: "Este mes", value: Fmt.tokens(store.monthTokens)),
            Row(label: "Daño por token", value: damage),
            Row(label: "Bonus de colección", value: "+\(Fmt.rate(store.collectionBonus)) por \(store.pokedexCaptured)/251"),
            Row(label: "Rango", value: "\(store.rank.label) · \(store.medals)/16 medallas"),
            Row(label: "Especies conseguidas", value: "\(store.speciesCaught) / 251"),
            Row(label: "Capturas totales", value: Fmt.tokens(store.state.box.count)),
        ]
        switch style {
        case .popover:
            rows.insert(
                Row(label: "Eventos registrados", value: Fmt.tokens(store.state.ledger.eventCount)),
                at: 4
            )
        case .hud:
            // En el HUD no hay tarjeta de compañero con su progreso, así que lo
            // que le falta para evolucionar va aquí.
            if let next = store.activeNextForm,
               let remaining = store.stage.tokensToNext(from: store.activeTokensEarned) {
                rows.append(Row(label: "\(next.localizedName) en", value: Fmt.tokens(remaining)))
            } else {
                rows.append(Row(label: "Evolución", value: store.stage.label))
            }
        }
        return rows
    }

    /// Contra quién, porque con un jefe abierto no hay salvaje y su tasa es 0.
    private var damage: String {
        guard let target = store.currentTarget else { return "sin rival ahora mismo" }
        return "\(Fmt.rate(target.rate)) a \(target.label)"
    }
}
