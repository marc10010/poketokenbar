import Foundation

/// Un montón de capturas indistinguibles: misma especie, misma variante de
/// color y misma etapa evolutiva alcanzada. La caja PC se apila así porque el
/// número de capturas no tiene techo, pero el de combinaciones sí
/// (251 especies × 2 variantes × 3 etapas).
///
/// La etapa es la que **cada Pokémon se ha ganado** estando equipado, no algo
/// derivado del histórico global: un Pineco capturado hoy sigue siendo Pineco
/// hasta que lo lleves tú.
public struct BoxGroup: Identifiable, Hashable, Sendable {
    /// La especie tal cual se capturó.
    public let species: Pokemon
    /// Cómo se dibuja ahora, según los tokens que ha ganado.
    public let displayForm: Pokemon
    public let stage: EvolutionStage
    public let isShiny: Bool
    public let count: Int
    /// Ejemplar que se equipa al elegir el grupo: el más adelantado, y entre
    /// iguales el más reciente.
    public let representative: CapturedPokemon
    public let latestCapturedAt: Date

    public var id: String { "\(species.id)-\(stage.rawValue)-\(isShiny)" }
    /// Con qué paleta se dibuja: un shiny puede mostrarse en normal.
    public var displaysShiny: Bool { representative.displaysShiny }
    public var hasEvolved: Bool { displayForm.id != species.id }

    public init(
        species: Pokemon,
        displayForm: Pokemon,
        stage: EvolutionStage,
        isShiny: Bool,
        count: Int,
        representative: CapturedPokemon,
        latestCapturedAt: Date
    ) {
        self.species = species
        self.displayForm = displayForm
        self.stage = stage
        self.isShiny = isShiny
        self.count = count
        self.representative = representative
        self.latestCapturedAt = latestCapturedAt
    }

    /// Agrupa por especie capturada, variante y etapa alcanzada.
    public static func group(
        _ box: [CapturedPokemon],
        pokedex: Pokedex,
        evolution: EvolutionService
    ) -> [BoxGroup] {
        var buckets: [String: [CapturedPokemon]] = [:]

        for captured in box {
            let stage = evolution.stage(of: captured)
            buckets["\(captured.speciesID)-\(stage.rawValue)-\(captured.isShiny)", default: []].append(captured)
        }

        return buckets.compactMap { _, members -> BoxGroup? in
            guard let representative = members.max(by: { ($0.tokensEarned, $0.capturedAt.timeIntervalSince1970) < ($1.tokensEarned, $1.capturedAt.timeIntervalSince1970) }),
                  let species = pokedex[representative.speciesID],
                  let newest = members.map(\.capturedAt).max()
            else { return nil }
            return BoxGroup(
                species: species,
                displayForm: evolution.currentForm(of: representative),
                stage: evolution.stage(of: representative),
                isShiny: representative.isShiny,
                count: members.count,
                representative: representative,
                latestCapturedAt: newest
            )
        }
        // Orden Pokédex, y dentro de una especie las etapas más altas después.
        .sorted {
            ($0.species.id, $0.stage.rawValue, $0.isShiny ? 1 : 0)
                < ($1.species.id, $1.stage.rawValue, $1.isShiny ? 1 : 0)
        }
    }
}
