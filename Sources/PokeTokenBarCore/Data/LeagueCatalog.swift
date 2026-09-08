import Foundation

/// Catálogo de ligas. Curado a mano, como gimnasios e hitos.
public final class LeagueCatalog: @unchecked Sendable {
    public static let shared: LeagueCatalog = {
        do {
            return try LeagueCatalog(bundle: .module)
        } catch {
            fatalError("leagues.json no se pudo cargar: \(error)")
        }
    }()

    /// En orden: primero Johto, luego Monte Plateado.
    public let all: [League]
    private let byID: [String: League]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "leagues", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(LeagueCatalogFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw CatalogError.unsupportedSchema(decoded.schemaVersion) }
        all = decoded.leagues
        byID = Dictionary(uniqueKeysWithValues: decoded.leagues.map { ($0.id, $0) })
    }

    public subscript(id: String) -> League? { byID[id] }

    /// La liga anterior en el orden, que hay que superar antes.
    public func previous(of league: League) -> League? {
        guard let index = all.firstIndex(where: { $0.id == league.id }), index > 0 else { return nil }
        return all[index - 1]
    }

    public enum CatalogError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "leagues.json no está en el bundle"
            case .unsupportedSchema(let version): return "schemaVersion \(version) no soportada"
            }
        }
    }
}
