import Foundation

/// Resultado de cruzar los tipos del compañero con los del rival.
public struct TypeMatchup: Hashable, Sendable {
    /// Multiplicador tal cual sale de la tabla (puede ser 0 = inmune).
    public let raw: Double
    /// El que se aplica de verdad, con suelo para que ningún token se pierda.
    public let multiplier: Double
    public let attacking: String?

    public init(raw: Double, multiplier: Double, attacking: String?) {
        self.raw = raw
        self.multiplier = multiplier
        self.attacking = attacking
    }

    public var isImmune: Bool { raw == 0 }
    public var isNeutral: Bool { raw == 1 }

    public var label: String {
        if isImmune { return "Inmune · daño mínimo" }
        switch raw {
        case 4...: return "Súper eficaz"
        case 2..<4: return "Muy eficaz"
        case 1: return "Neutro"
        default: return "Poco eficaz"
        }
    }

    public var badge: String {
        let formatted = multiplier == multiplier.rounded()
            ? String(format: "%.0f", multiplier)
            : String(format: "%.2f", multiplier).replacingOccurrences(of: "0.25", with: "¼").replacingOccurrences(of: "0.50", with: "½")
        return "×\(formatted)"
    }

    public static let neutral = TypeMatchup(raw: 1, multiplier: 1, attacking: nil)
}

/// Tabla de efectividad de tipos, generada desde PokeAPI
/// (`tools/generate_typechart.mjs`). Incluye Hada porque la Pokédex embebida
/// trae los tipos actuales: Clefairy y compañía son Hada desde Gen 6.
public final class TypeChart: @unchecked Sendable {
    public static let shared: TypeChart = {
        do {
            return try TypeChart(bundle: .module)
        } catch {
            fatalError("typechart.json no se pudo cargar: \(error)")
        }
    }()

    public let types: [String]
    private let effectiveness: [String: [String: Double]]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "typechart", withExtension: "json") else {
            throw ChartError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(TypeChartFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw ChartError.unsupportedSchema(decoded.schemaVersion) }
        types = decoded.types
        effectiveness = decoded.effectiveness
    }

    /// Multiplicador de un tipo atacante contra un defensor. Lo que no está en
    /// la tabla es neutro.
    public func factor(attacker: String, defender: String) -> Double {
        effectiveness[attacker]?[defender] ?? 1
    }

    /// Contra un defensor de uno o dos tipos, los factores se multiplican.
    public func factor(attacker: String, defender: [String]) -> Double {
        defender.reduce(1) { $0 * factor(attacker: attacker, defender: $1) }
    }

    /// El compañero ataca con su mejor tipo: de los suyos, el que más daño
    /// haga. Un tipo inmune no condena el combate si el otro sirve.
    public func matchup(attacker: [String], defender: [String]) -> TypeMatchup {
        guard !attacker.isEmpty, !defender.isEmpty else { return .neutral }
        var best = (type: attacker[0], factor: factor(attacker: attacker[0], defender: defender))
        for type in attacker.dropFirst() {
            let candidate = factor(attacker: type, defender: defender)
            if candidate > best.factor { best = (type, candidate) }
        }
        return TypeMatchup(
            raw: best.factor,
            multiplier: max(GameRules.minimumDamageMultiplier, min(best.factor, GameRules.maximumDamageMultiplier)),
            attacking: best.type
        )
    }

    public enum ChartError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "typechart.json no está en el bundle"
            case .unsupportedSchema(let version): return "schemaVersion \(version) no soportada"
            }
        }
    }
}

public struct TypeChartFile: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let source: String
    public let types: [String]
    public let effectiveness: [String: [String: Double]]
}
