import Foundation

/// Un consumo de tokens observado por alguna `TokenSource`.
/// `id` debe ser estable para el mismo consumo real: es la clave de idempotencia.
public struct UsageEvent: Codable, Hashable, Sendable {
    public let id: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let timestamp: Date
    public let origin: String

    public init(
        id: String,
        model: String = "unknown",
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        timestamp: Date = Date(),
        origin: String = "unknown"
    ) {
        self.id = id
        self.model = model
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cacheCreationTokens = max(0, cacheCreationTokens)
        self.cacheReadTokens = max(0, cacheReadTokens)
        self.timestamp = timestamp
        self.origin = origin
    }

    /// Tokens que cuentan como daño. Los de caché son opcionales porque en
    /// sesiones largas dominan el total y desequilibran el combate.
    public func damage(countingCache: Bool) -> Int {
        let base = inputTokens + outputTokens
        return countingCache ? base + cacheCreationTokens + cacheReadTokens : base
    }
}
