import Foundation

/// Banda del reloj local. El juego no tiene piedras evolutivas ni amistad, así
/// que lo que decide una rama es lo que sí tiene: la hora y el rival.
public enum ClockBand: String, Hashable, Sendable, CaseIterable {
    case day
    case night
    case morning
    case afternoon

    public var label: String {
        switch self {
        case .day: return "de día (6:00–19:59)"
        case .night: return "de noche (20:00–5:59)"
        case .morning: return "por la mañana (6:00–13:59)"
        case .afternoon: return "por la tarde (14:00–19:59)"
        }
    }

    public func contains(_ hour: Int) -> Bool {
        switch self {
        case .day: return (6...19).contains(hour)
        case .night: return hour >= 20 || hour < 6
        case .morning: return (6...13).contains(hour)
        case .afternoon: return (14...19).contains(hour)
        }
    }

    public static func current(at date: Date, calendar: Calendar = .current) -> [ClockBand] {
        let hour = calendar.component(.hour, from: date)
        return allCases.filter { $0.contains(hour) }
    }

    /// Si es de día, para el indicador de la barra de menú.
    public static func isDaylight(at date: Date, calendar: Calendar = .current) -> Bool {
        ClockBand.day.contains(calendar.component(.hour, from: date))
    }
}

/// Qué hace que una línea tome una rama y no otra.
public enum BranchCondition: Hashable, Sendable {
    /// Vencer un salvaje de este tipo. Es la traducción de las piedras
    /// evolutivas: no hay objetos, pero sí rivales con tipo.
    case defeatedType(String)
    /// Estar en esta banda del reloj.
    case clock(ClockBand)
    /// La que sale si no se cumple ninguna otra.
    case otherwise

    public var label: String {
        switch self {
        case .defeatedType(let type): return "vence un rival de tipo \(TypeNames.spanish(type))"
        case .clock(let band): return band.label
        case .otherwise: return "cualquier otra cosa"
        }
    }
}

/// Nombres de tipo en castellano. Viven aquí porque las condiciones de rama se
/// enseñan en la ficha y la UI no debe traducir datos del motor.
public enum TypeNames {
    public static func spanish(_ type: String) -> String {
        switch type {
        case "water": return "agua"
        case "electric": return "eléctrico"
        case "fire": return "fuego"
        case "grass": return "planta"
        case "psychic": return "psíquico"
        case "dark": return "siniestro"
        default: return type
        }
    }
}

/// Reglas de rama de las cinco líneas que bifurcan, traducidas del canon.
///
/// Curadas a mano, como `gyms.json`: PokeAPI trae la cadena evolutiva pero su
/// condición es un objeto o un intercambio que este juego no tiene. El orden
/// **importa**: se evalúa de arriba abajo, así que el tipo del rival manda
/// sobre el reloj y `otherwise` va siempre al final.
public enum BranchRules {
    /// forma que bifurca → ramas en orden de prioridad.
    public static let table: [Int: [(form: Int, condition: BranchCondition)]] = [
        // Eevee: las tres piedras pasan a ser el tipo del rival vencido, y
        // Espeon/Umbreon se quedan con el día y la noche, que es su canon.
        133: [
            (134, .defeatedType("water")),      // Vaporeon · Piedra Agua
            (135, .defeatedType("electric")),   // Jolteon · Piedra Trueno
            (136, .defeatedType("fire")),       // Flareon · Piedra Fuego
            (196, .clock(.day)),                // Espeon · amistad + día
            (197, .clock(.night)),              // Umbreon · amistad + noche
        ],
        // Gloom: Piedra Solar de día, Piedra Hoja de noche.
        44: [
            (182, .clock(.day)),                // Bellossom
            (45, .clock(.night)),               // Vileplume
        ],
        // Poliwhirl: Piedra Agua contra un rival de agua; Politoed pedía un
        // intercambio, que no existe, así que es la rama por defecto.
        61: [
            (62, .defeatedType("water")),       // Poliwrath
            (186, .otherwise),                  // Politoed
        ],
        // Slowpoke: Slowbro por nivel (de día), Slowking pedía Roca del Rey.
        79: [
            (80, .clock(.day)),                 // Slowbro
            (199, .clock(.night)),              // Slowking
        ],
        // Tyrogue: el canon mira Ataque contra Defensa, que aquí no varía, así
        // que lo decide la banda del reloj en tres tramos.
        236: [
            (106, .clock(.morning)),            // Hitmonlee
            (107, .clock(.afternoon)),          // Hitmonchan
            (237, .clock(.night)),              // Hitmontop
        ],
    ]

    public static func branches(of formID: Int) -> [(form: Int, condition: BranchCondition)] {
        table[formID] ?? []
    }

    public static var branchingForms: Set<Int> { Set(table.keys) }

    /// Qué rama toca ahora mismo: con lo vencido y con el reloj.
    ///
    /// - Parameters:
    ///   - defeatedTypes: tipos del último salvaje vencido. Es lo que decide,
    ///     por encima del reloj: el jugador puede buscarlo a propósito.
    public static func resolve(
        formID: Int,
        defeatedTypes: [String],
        at date: Date,
        calendar: Calendar = .current
    ) -> Int? {
        let options = branches(of: formID)
        guard !options.isEmpty else { return nil }
        let bands = Set(ClockBand.current(at: date, calendar: calendar))

        for option in options {
            switch option.condition {
            case .defeatedType(let type) where defeatedTypes.contains(type): return option.form
            case .clock(let band) where bands.contains(band): return option.form
            case .otherwise: return option.form
            default: continue
            }
        }
        // Sin condición cumplida no se deja colgado: la primera rama.
        return options.first?.form
    }
}
