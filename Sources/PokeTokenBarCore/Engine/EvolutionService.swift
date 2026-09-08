import Foundation

public enum EvolutionStage: Int, CaseIterable, Sendable {
    case base = 0
    case one = 1
    case two = 2

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

    /// Camino completo desde la forma base, de longitud 1...3.
    public func chainPath(of captured: CapturedPokemon, maxSteps: Int = EvolutionStage.two.rawValue) -> [Pokemon] {
        let baseID = pokedex.require(captured.speciesID).baseFormID
        var path = [pokedex.require(baseID)]
        var rng = SeededRandomProvider(seed: captured.evolutionSeed)
        while path.count <= maxSteps {
            let options = path[path.count - 1].evolvesInto.compactMap { pokedex[$0] }
            guard !options.isEmpty else { break }
            path.append(options[rng.nextInt(in: 0...(options.count - 1))])
        }
        return path
    }

    public func currentForm(of captured: CapturedPokemon, totalTokens: Int) -> Pokemon {
        let path = chainPath(of: captured)
        let index = min(EvolutionStage.stage(forTotalTokens: totalTokens).rawValue, path.count - 1)
        return path[index]
    }

    /// Forma inmediatamente posterior a la actual, si la etapa y la cadena la permiten.
    public func nextForm(of captured: CapturedPokemon, totalTokens: Int) -> Pokemon? {
        guard let _ = EvolutionStage.stage(forTotalTokens: totalTokens).tokensToNext(from: totalTokens) else { return nil }
        let path = chainPath(of: captured)
        let next = EvolutionStage.stage(forTotalTokens: totalTokens).rawValue + 1
        return next < path.count ? path[next] : nil
    }
}
