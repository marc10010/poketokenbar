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

    /// Camino completo de la línea, de longitud 1...3, **pasando por la especie
    /// capturada**: primero se sube hasta la forma base y luego se baja con la
    /// rama que fije la semilla.
    ///
    /// Empezar en `baseFormID` a secas no sirve: si la captura ya viene
    /// evolucionada (o es de una rama que la semilla no habría elegido) su
    /// propia forma no estaría en el camino.
    public func chainPath(of captured: CapturedPokemon, maxSteps: Int = EvolutionStage.two.rawValue) -> [Pokemon] {
        let species = pokedex.require(captured.speciesID)
        var path = [species]
        while path.count <= maxSteps + 1, let parent = pokedex.parent(of: path[0].id) {
            path.insert(parent, at: 0)
        }
        var rng = SeededRandomProvider(seed: captured.evolutionSeed)
        while path.count <= maxSteps {
            let options = path[path.count - 1].evolvesInto.compactMap { pokedex[$0] }
            guard !options.isEmpty else { break }
            path.append(options[rng.nextInt(in: 0...(options.count - 1))])
        }
        return path
    }

    /// Etapa en la que está: la que le dan sus tokens, pero **nunca por debajo
    /// del sitio que ya ocupaba al capturarlo**. Sin ese suelo, un Pokémon
    /// capturado ya evolucionado retrocedería hasta ganar tokens: un Pikachu
    /// se dibujaría como Pichu.
    public func stage(of captured: CapturedPokemon) -> EvolutionStage {
        let earned = EvolutionStage.stage(forTotalTokens: captured.tokensEarned)
        let floor = pokedex.require(captured.speciesID).stage
        guard floor > earned.rawValue else { return earned }
        return EvolutionStage(rawValue: floor) ?? earned
    }

    public func currentForm(of captured: CapturedPokemon) -> Pokemon {
        let path = chainPath(of: captured)
        let index = min(stage(of: captured).rawValue, path.count - 1)
        return path[index]
    }

    /// Forma inmediatamente posterior a la actual, si la etapa y la cadena la permiten.
    public func nextForm(of captured: CapturedPokemon) -> Pokemon? {
        let current = stage(of: captured)
        guard current.tokensToNext(from: captured.tokensEarned) != nil else { return nil }
        let path = chainPath(of: captured)
        let next = current.rawValue + 1
        return next < path.count ? path[next] : nil
    }
}
