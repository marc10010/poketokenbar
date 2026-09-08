import Foundation

/// Criterios para recortar la caja PC. Es lógica pura sobre `[BoxGroup]` para
/// poder probarla sin UI: la caja crece sin techo en capturas y a partir de
/// unas decenas de huecos hace falta buscar, no hacer scroll.
public struct BoxFilter: Hashable, Sendable {
    public enum Sort: String, CaseIterable, Hashable, Sendable {
        case dex
        case recent
        case count
        case rarity

        public var label: String {
            switch self {
            case .dex: return "Nº de Pokédex"
            case .recent: return "Captura más reciente"
            case .count: return "Más repetidos"
            case .rarity: return "Rareza"
            }
        }
    }

    public var query: String = ""
    /// Vacío = todos los tipos.
    public var types: Set<String> = []
    public var onlyShiny = false
    public var onlyEvolved = false
    /// `nil` = las dos generaciones.
    public var generation: Int?
    public var sort: Sort = .dex

    public init() {}

    public var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            || !types.isEmpty
            || onlyShiny
            || onlyEvolved
            || generation != nil
    }

    /// Descripción corta de lo que está filtrando, para la propia UI.
    public var activeSummary: [String] {
        var parts: [String] = []
        if !types.isEmpty { parts.append(types.sorted().joined(separator: ", ")) }
        if onlyShiny { parts.append("shiny") }
        if onlyEvolved { parts.append("evolucionados") }
        if let generation { parts.append("gen \(generation)") }
        return parts
    }

    public mutating func reset() {
        self = BoxFilter()
    }

    public func apply(to groups: [BoxGroup]) -> [BoxGroup] {
        let needle = Self.normalize(query)
        let matching = groups.filter { group in
            if !types.isEmpty, types.isDisjoint(with: Set(group.species.types + group.displayForm.types)) {
                return false
            }
            if onlyShiny, !group.isShiny { return false }
            if onlyEvolved, !group.hasEvolved { return false }
            if let generation, group.species.generation != generation { return false }
            return needle.isEmpty || Self.matches(group, needle: needle)
        }
        return sorted(matching)
    }

    /// Busca por nombre (en español o inglés, con o sin acentos), por la forma
    /// evolucionada y por número de Pokédex, con o sin `#` y con o sin ceros.
    static func matches(_ group: BoxGroup, needle: String) -> Bool {
        let haystacks = [
            normalize(group.species.localizedName),
            normalize(group.species.name),
            normalize(group.displayForm.localizedName),
            normalize(group.displayForm.name),
        ]
        if haystacks.contains(where: { $0.contains(needle) }) { return true }

        let digits = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        let padded = String(format: "%03d", group.species.id)
        return "\(group.species.id)" == digits || padded == String(format: "%03d", Int(digits) ?? -1)
    }

    /// Plegado usado por la búsqueda: sin acentos, sin distinguir mayúsculas.
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
    }

    private func sorted(_ groups: [BoxGroup]) -> [BoxGroup] {
        switch sort {
        case .dex:
            return groups.sorted {
                ($0.species.id, $0.stage.rawValue, $0.isShiny ? 1 : 0)
                    < ($1.species.id, $1.stage.rawValue, $1.isShiny ? 1 : 0)
            }
        case .recent:
            return groups.sorted { $0.latestCapturedAt > $1.latestCapturedAt }
        case .count:
            return groups.sorted { ($0.count, -$0.species.id) > ($1.count, -$1.species.id) }
        case .rarity:
            return groups.sorted {
                ($0.species.rarity.sortIndex, $0.species.id) < ($1.species.rarity.sortIndex, $1.species.id)
            }
        }
    }
}
