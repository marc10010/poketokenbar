import Foundation

/// Un hueco de la Pokédex completa: los 251, tengas lo que tengas.
public struct PokedexEntry: Identifiable, Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        /// Está en tu caja, o es la forma en la que se ve algo de tu caja.
        case captured
        /// Le has ganado en libertad pero no se quedó (línea repetida).
        case defeated
        case unknown

        public var label: String {
            switch self {
            case .captured: return "En la caja"
            case .defeated: return "Visto"
            case .unknown: return "Sin ver"
            }
        }
    }

    public let species: Pokemon
    public let state: State
    /// El grupo de la caja al que corresponde, si lo tienes.
    public let group: BoxGroup?
    /// Veces que has vencido a su línea en libertad.
    public let defeats: Int

    public var id: Int { species.id }
    public var isCaptured: Bool { state == .captured }

    public init(species: Pokemon, state: State, group: BoxGroup?, defeats: Int) {
        self.species = species
        self.state = state
        self.group = group
        self.defeats = defeats
    }

    /// Construye la Pokédex entera.
    ///
    /// Cuenta como capturada la especie con la que se capturó **y** la forma en
    /// la que se ve ahora: si tu Squirtle ya es Wartortle, los dos huecos están
    /// llenos, pero Blastoise sigue vacío hasta que evolucione. Marcar la línea
    /// entera inflaría el contador con formas que no has visto nunca.
    public static func build(
        pokedex: Pokedex,
        boxGroups: [BoxGroup],
        familyDefeats: [Int: Int]
    ) -> [PokedexEntry] {
        var groupsBySpecies: [Int: BoxGroup] = [:]
        for group in boxGroups {
            groupsBySpecies[group.species.id] = group
            groupsBySpecies[group.displayForm.id] = group
        }

        return pokedex.all.map { species in
            let defeats = familyDefeats[species.baseFormID] ?? 0
            let group = groupsBySpecies[species.id]
            let state: State = group != nil ? .captured : (defeats > 0 ? .defeated : .unknown)
            return PokedexEntry(species: species, state: state, group: group, defeats: defeats)
        }
    }
}

/// Recorte de la Pokédex: buscar y filtrar sobre los 251 huecos.
public struct PokedexFilter: Hashable, Sendable {
    public var query: String = ""
    public var types: Set<String> = []
    public var generation: Int?
    public var onlyMissing = false
    public var onlyCaptured = false

    public init() {}

    public var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            || !types.isEmpty
            || generation != nil
            || onlyMissing
            || onlyCaptured
    }

    public mutating func reset() { self = PokedexFilter() }

    public func apply(to entries: [PokedexEntry]) -> [PokedexEntry] {
        let needle = BoxFilter.normalize(query)
        return entries.filter { entry in
            if onlyMissing, entry.isCaptured { return false }
            if onlyCaptured, !entry.isCaptured { return false }
            if let generation, entry.species.generation != generation { return false }
            if !types.isEmpty, types.isDisjoint(with: Set(entry.species.types)) { return false }
            guard !needle.isEmpty else { return true }
            if BoxFilter.normalize(entry.species.localizedName).contains(needle) { return true }
            if BoxFilter.normalize(entry.species.name).contains(needle) { return true }
            let digits = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
            return Int(digits) == entry.species.id
        }
    }
}
