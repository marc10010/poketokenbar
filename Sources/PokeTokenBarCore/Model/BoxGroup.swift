import Foundation

/// Un montón de capturas que se ven igual: misma forma visible y misma variante
/// de color. La caja PC se muestra apilada así porque el número de capturas no
/// tiene techo, pero el de formas distintas sí (251 especies × 2 variantes).
public struct BoxGroup: Identifiable, Hashable, Sendable {
    public let form: Pokemon
    public let isShiny: Bool
    public let count: Int
    /// Ejemplar que se equipa al elegir el grupo: el más reciente.
    public let representative: CapturedPokemon
    public let latestCapturedAt: Date

    public var id: String { "\(form.id)-\(isShiny)" }

    public init(form: Pokemon, isShiny: Bool, count: Int, representative: CapturedPokemon, latestCapturedAt: Date) {
        self.form = form
        self.isShiny = isShiny
        self.count = count
        self.representative = representative
        self.latestCapturedAt = latestCapturedAt
    }

    /// Agrupa por forma visible: dos ejemplares de la misma línea que hoy se
    /// dibujan igual cuentan como uno, y se separan solos si el histórico de
    /// tokens los lleva por ramas evolutivas distintas.
    public static func group(
        _ box: [CapturedPokemon],
        totalTokens: Int,
        evolution: EvolutionService
    ) -> [BoxGroup] {
        var buckets: [String: [CapturedPokemon]] = [:]
        var forms: [String: Pokemon] = [:]

        for captured in box {
            let form = evolution.currentForm(of: captured, totalTokens: totalTokens)
            let key = "\(form.id)-\(captured.isShiny)"
            buckets[key, default: []].append(captured)
            forms[key] = form
        }

        return buckets.compactMap { key, members -> BoxGroup? in
            guard let form = forms[key],
                  let newest = members.max(by: { $0.capturedAt < $1.capturedAt })
            else { return nil }
            return BoxGroup(
                form: form,
                isShiny: newest.isShiny,
                count: members.count,
                representative: newest,
                latestCapturedAt: newest.capturedAt
            )
        }
        // Orden Pokédex: estable y acotado, al contrario que el de captura.
        .sorted { ($0.form.id, $0.isShiny ? 1 : 0) < ($1.form.id, $1.isShiny ? 1 : 0) }
    }
}
