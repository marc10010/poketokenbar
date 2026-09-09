import Foundation

/// Cómo se dibuja la caja: huecos con sprite, o filas con los números a la
/// vista. La caja guarda mucho más dato por Pokémon que la vista de combate y
/// en rejilla solo cabe el sprite.
public enum BoxDensity: String, Codable, CaseIterable, Hashable, Sendable {
    case rejilla
    case lista

    public var label: String {
        switch self {
        case .rejilla: return "Rejilla"
        case .lista: return "Lista"
        }
    }
}

/// Tramo con cabecera dentro de la caja. Una rejilla plana de doscientos
/// huecos no tiene puntos de referencia: sabes buscar lo que ya conoces, pero
/// no situarte. Los tramos salen del orden activo, así que la cabecera siempre
/// dice por qué ese hueco está ahí.
public struct BoxSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let groups: [BoxGroup]

    public init(id: String, title: String, groups: [BoxGroup]) {
        self.id = id
        self.title = title
        self.groups = groups
    }

    /// Parte una lista **ya ordenada** en tramos consecutivos. Agrupar por
    /// tramos contiguos y no por clave garantiza que las cabeceras respeten el
    /// orden que pidió el usuario en vez de imponer otro.
    public static func build(
        _ groups: [BoxGroup],
        sort: BoxFilter.Sort,
        wins: (Int) -> Int = { _ in 0 }
    ) -> [BoxSection] {
        var sections: [BoxSection] = []
        for group in groups {
            let (key, title) = bucket(group, sort: sort, wins: wins(group.species.id))
            if let last = sections.last, last.id == key {
                sections[sections.count - 1] = BoxSection(id: key, title: title, groups: last.groups + [group])
            } else {
                sections.append(BoxSection(id: key, title: title, groups: [group]))
            }
        }
        return sections
    }

    private static func bucket(_ group: BoxGroup, sort: BoxFilter.Sort, wins: Int) -> (String, String) {
        switch sort {
        case .dex:
            return ("gen-\(group.species.generation)", group.species.regionLabel)
        case .rarity:
            let rarity = group.species.rarity
            return ("rarity-\(rarity.rawValue)", rarity.label)
        case .recent:
            let key = TokenLedger.monthKey(for: group.latestCapturedAt)
            return ("month-\(key)", monthLabel(key))
        case .wins:
            let band = winBand(wins)
            return ("wins-\(band.0)", band.1)
        }
    }

    public static func winBand(_ wins: Int) -> (Int, String) {
        switch wins {
        case 0: return (0, "Sin victorias contra su línea")
        case 1...4: return (1, "De 1 a 4 victorias")
        case 5...19: return (2, "De 5 a 19 victorias")
        default: return (3, "20 victorias o más")
        }
    }

    public static func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
            return key
        }
        let names = [
            "enero", "febrero", "marzo", "abril", "mayo", "junio",
            "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
        ]
        return "\(names[month - 1].capitalized) de \(year)"
    }
}

/// Movimiento de la selección con el teclado. Recorrer doscientos huecos a
/// ratón es el problema que tiene la caja, así que la selección se mueve con
/// las flechas y equipar es una tecla.
public enum BoxMove: Sendable {
    case left
    case right
    case up
    case down
}

extension BoxSection {
    /// Hueco al que va la selección. Cada tramo empieza fila nueva, así que
    /// subir desde la primera fila de un tramo cae en la última del anterior
    /// conservando la columna, no en un hueco arbitrario.
    public static func move(
        _ direction: BoxMove,
        from id: String?,
        in sections: [BoxSection],
        columns: Int
    ) -> String? {
        let columns = max(1, columns)
        guard !sections.isEmpty else { return nil }
        guard let id, let position = locate(id, in: sections) else {
            return sections.first?.groups.first?.id
        }
        let (s, i) = position
        let items = sections[s].groups

        switch direction {
        case .left:
            if i > 0 { return items[i - 1].id }
            return s > 0 ? sections[s - 1].groups.last?.id : id
        case .right:
            if i + 1 < items.count { return items[i + 1].id }
            return s + 1 < sections.count ? sections[s + 1].groups.first?.id : id
        case .up:
            if i >= columns { return items[i - columns].id }
            guard s > 0 else { return id }
            let previous = sections[s - 1].groups
            let lastRowStart = ((previous.count - 1) / columns) * columns
            return previous[min(lastRowStart + i % columns, previous.count - 1)].id
        case .down:
            if i + columns < items.count { return items[i + columns].id }
            // Bajar desde la última fila: al tramo siguiente, misma columna.
            let onLastRow = i / columns == (items.count - 1) / columns
            guard onLastRow, s + 1 < sections.count else {
                return onLastRow ? id : items[items.count - 1].id
            }
            let next = sections[s + 1].groups
            return next[min(i % columns, next.count - 1)].id
        }
    }

    private static func locate(_ id: String, in sections: [BoxSection]) -> (Int, Int)? {
        for (s, section) in sections.enumerated() {
            if let i = section.groups.firstIndex(where: { $0.id == id }) { return (s, i) }
        }
        return nil
    }
}
