import Foundation

/// Catálogo de zonas. Los encuentros vienen de PokeAPI filtrados a Gen 1 y 2;
/// el agrupamiento de las 163 áreas en zonas jugables es curado
/// (`tools/generate_zones.mjs`).
public final class ZoneCatalog: @unchecked Sendable {
    public static let shared: ZoneCatalog = {
        do {
            return try ZoneCatalog(bundle: .module)
        } catch {
            fatalError("zones.json no se pudo cargar: \(error)")
        }
    }()

    public let all: [Zone]
    /// Sin encuentro salvaje en Gen 1/2. Red de seguridad: se ofrecen en
    /// cualquier zona, pero solo en el tier más difícil entre "raro" y el
    /// suyo, para que un legendario no se abarate.
    public let unassigned: Set<Int>
    private let byID: [String: Zone]
    private let zonesBySpecies: [Int: [Zone]]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "zones", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(ZoneCatalogFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw CatalogError.unsupportedSchema(decoded.schemaVersion) }
        all = decoded.zones
        unassigned = Set(decoded.unassigned)
        byID = Dictionary(uniqueKeysWithValues: decoded.zones.map { ($0.id, $0) })

        var index: [Int: [Zone]] = [:]
        for zone in decoded.zones {
            for species in zone.species { index[species, default: []].append(zone) }
        }
        zonesBySpecies = index
    }

    public subscript(id: String) -> Zone? { byID[id] }

    public func zones(for speciesID: Int) -> [Zone] { zonesBySpecies[speciesID] ?? [] }

    public func unlocked(_ access: ZoneAccess) -> [Zone] {
        all.filter { access.opens($0) }
    }

    /// Especies que pueden aparecer con este progreso.
    public func availableSpecies(_ access: ZoneAccess) -> Set<Int> {
        unlocked(access).reduce(into: Set<Int>()) { $0.formUnion($1.species) }
    }

    /// Si una especie tiene alguna zona abierta.
    public func isAvailable(_ speciesID: Int, _ access: ZoneAccess) -> Bool {
        zones(for: speciesID).contains { access.opens($0) }
    }

    public enum CatalogError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "zones.json no está en el bundle"
            case .unsupportedSchema(let version): return "schemaVersion \(version) no soportada"
            }
        }
    }
}
