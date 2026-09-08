import Foundation

/// Catálogo de gimnasios embebido. Curado a mano: PokeAPI no tiene líderes.
public final class GymCatalog: @unchecked Sendable {
    public static let shared: GymCatalog = {
        do {
            return try GymCatalog(bundle: .module)
        } catch {
            fatalError("gyms.json no se pudo cargar: \(error)")
        }
    }()

    /// En orden de reto: los ocho de Johto y luego los de Kanto.
    public let all: [Gym]
    private let byID: [String: Gym]

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "gyms", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(GymCatalogFile.self, from: data)
        guard decoded.schemaVersion == 1 else { throw CatalogError.unsupportedSchema(decoded.schemaVersion) }
        all = decoded.gyms.sorted { $0.order < $1.order }
        byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    public subscript(id: String) -> Gym? { byID[id] }

    public var count: Int { all.count }

    /// El siguiente gimnasio por afrontar: el primero del orden que no esté
    /// derrotado. `nil` si están todos.
    public func next(defeated: Set<String>) -> Gym? {
        all.first { !defeated.contains($0.id) }
    }

    public func medals(defeated: Set<String>) -> [Gym] {
        all.filter { defeated.contains($0.id) }
    }

    public enum CatalogError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .resourceMissing: return "gyms.json no está en el bundle"
            case .unsupportedSchema(let version): return "schemaVersion \(version) no soportada"
            }
        }
    }
}
