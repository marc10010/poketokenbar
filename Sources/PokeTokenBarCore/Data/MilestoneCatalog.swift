import Foundation

/// Catálogo de hitos legendarios. Curado a mano, como el de gimnasios.
public final class MilestoneCatalog: @unchecked Sendable {
    public static let shared: MilestoneCatalog = {
        do {
            return try MilestoneCatalog(bundle: .module)
        } catch {
            fatalError("milestones.json no se pudo cargar: \(error)")
        }
    }()

    public let all: [Milestone]
    private let byID: [String: Milestone]
    private let bySpecies: [Int: Milestone]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "milestones", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(MilestoneCatalogFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw CatalogError.unsupportedSchema(decoded.schemaVersion) }
        all = decoded.milestones
        byID = Dictionary(uniqueKeysWithValues: decoded.milestones.map { ($0.id, $0) })
        bySpecies = Dictionary(decoded.milestones.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public subscript(id: String) -> Milestone? { byID[id] }

    public func milestone(forSpecies speciesID: Int) -> Milestone? { bySpecies[speciesID] }

    public enum CatalogError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "milestones.json no está en el bundle"
            case .unsupportedSchema(let version): return "schemaVersion \(version) no soportada"
            }
        }
    }
}
