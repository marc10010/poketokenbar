import Foundation

public enum EvolutionStage: Int, CaseIterable, Sendable {
    case base = 0
    case one = 1
    case two = 2

    /// `tokens` son los que ha ganado **ese** Pokémon estando equipado.
    public static func stage(forTotalTokens tokens: Int) -> EvolutionStage {
        if tokens >= GameRules.stageTwoThreshold { return .two }
        if tokens >= GameRules.stageOneThreshold { return .one }
        return .base
    }

    public var label: String {
        switch self {
        case .base: return "Etapa base"
        case .one: return "Etapa 1"
        case .two: return "Etapa 2"
        }
    }

    /// Tokens que faltan para la siguiente etapa. `nil` si ya está al máximo.
    public func tokensToNext(from tokens: Int) -> Int? {
        switch self {
        case .base: return max(0, GameRules.stageOneThreshold - tokens)
        case .one: return max(0, GameRules.stageTwoThreshold - tokens)
        case .two: return nil
        }
    }
}

/// Resuelve qué forma se muestra: camina la cadena evolutiva desde la forma
/// base tantos pasos como permita el histórico de tokens. Si la cadena bifurca
/// (Eevee, Gloom, Slowpoke, Tyrogue) la rama la fija `evolutionSeed`, que no
/// cambia nunca: el mismo Pokémon capturado evoluciona siempre igual.
public struct EvolutionService {
    private let pokedex: Pokedex

    public init(pokedex: Pokedex = .shared) {
        self.pokedex = pokedex
    }

    /// Camino que **ha recorrido** este ejemplar: su especie de captura y las
    /// formas en las que ha ido evolucionando, en orden.
    ///
    /// Antes se derivaba de la semilla, y por tanto la rama estaba echada desde
    /// la captura. Ahora la rama se decide al evolucionar (`BranchRules`) y
    /// queda escrita en el ejemplar, así que el camino es historia y no
    /// predicción.
    public func chainPath(of captured: CapturedPokemon) -> [Pokemon] {
        var path = [pokedex.require(captured.speciesID)]
        while let parent = pokedex.parent(of: path[0].id), path.count < 3 {
            path.insert(parent, at: 0)
        }
        for id in captured.evolvedForms {
            if let form = pokedex[id] { path.append(form) }
        }
        return path
    }

    /// Etapa en la que está: la de la forma que se ve. Sale de lo que ha
    /// evolucionado de verdad, no de sus tokens: los tokens dan **derecho** a
    /// evolucionar, la evolución la hace `resolveEvolution`.
    public func stage(of captured: CapturedPokemon) -> EvolutionStage {
        let form = currentForm(of: captured)
        return EvolutionStage(rawValue: min(EvolutionStage.two.rawValue, form.stage)) ?? .base
    }

    public func currentForm(of captured: CapturedPokemon) -> Pokemon {
        guard let last = captured.evolvedForms.last, let form = pokedex[last] else {
            return pokedex.require(captured.speciesID)
        }
        return form
    }

    /// Si ya tiene tokens de sobra para el siguiente salto. Es lo que la ficha
    /// enseña como "listo para evolucionar".
    public func canEvolve(_ captured: CapturedPokemon) -> Bool {
        guard !options(for: captured).isEmpty else { return false }
        return stage(of: captured).tokensToNext(from: captured.tokensEarned) == 0
    }

    /// Ramas posibles desde su forma actual.
    public func options(for captured: CapturedPokemon) -> [Pokemon] {
        currentForm(of: captured).evolvesInto.compactMap { pokedex[$0] }
    }

    /// A qué evolucionaría **ahora mismo**: con lo último que ha vencido y con
    /// la hora que es. Es lo que la ficha canta para que no haya que adivinar.
    public func branch(
        for captured: CapturedPokemon,
        defeatedTypes: [String],
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Pokemon? {
        let options = options(for: captured)
        guard !options.isEmpty else { return nil }
        guard options.count > 1 else { return options[0] }
        let form = currentForm(of: captured).id
        guard let resolved = BranchRules.resolve(
            formID: form,
            defeatedTypes: defeatedTypes,
            at: date,
            calendar: calendar
        ) else {
            // Cadena que bifurca sin regla escrita: desempate estable.
            var rng = SeededRandomProvider(seed: captured.evolutionSeed)
            return options[rng.nextInt(in: 0...(options.count - 1))]
        }
        return pokedex[resolved] ?? options[0]
    }

    /// Forma que viene después, para enseñar el progreso. `nil` si su línea
    /// acaba aquí o si ya está en la etapa máxima.
    public func nextForm(of captured: CapturedPokemon) -> Pokemon? {
        guard stage(of: captured).tokensToNext(from: captured.tokensEarned) != nil else { return nil }
        let options = options(for: captured)
        guard options.count == 1 else { return nil }
        return options[0]
    }
}
