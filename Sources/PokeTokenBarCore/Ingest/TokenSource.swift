import Foundation

/// Origen de eventos de consumo. La app puede tener varios activos a la vez;
/// `GameStore.ingest` deduplica por `UsageEvent.id`, así que solaparse es seguro.
public protocol TokenSource: AnyObject {
    var name: String { get }
    var statusDescription: String { get }
    func start(handler: @escaping (UsageEvent) -> Void)
    func stop()
}

/// Parseo del payload `usage` de la API de Anthropic, compartido por todas las fuentes.
public struct AnthropicUsagePayload: Decodable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_input_tokens"
        case cacheReadTokens = "cache_read_input_tokens"
    }

    public var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0 && cacheCreationTokens == 0 && cacheReadTokens == 0
    }
}
