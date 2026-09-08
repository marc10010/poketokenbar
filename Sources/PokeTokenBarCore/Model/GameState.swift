import Foundation

/// Un Pokémon guardado en la caja PC.
public struct CapturedPokemon: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Especie con la que se capturó (normalmente la forma base de su línea).
    public let speciesID: Int
    public let isShiny: Bool
    public let capturedAt: Date
    /// Tokens acumulados del jugador en el momento de la captura.
    public let capturedAtTotalTokens: Int
    /// Fija la rama evolutiva cuando la cadena bifurca (Eevee, Gloom, Tyrogue).
    public let evolutionSeed: UInt64
    public var nickname: String?

    public init(
        id: UUID = UUID(),
        speciesID: Int,
        isShiny: Bool,
        capturedAt: Date = Date(),
        capturedAtTotalTokens: Int,
        evolutionSeed: UInt64 = UInt64.random(in: 0..<UInt64.max),
        nickname: String? = nil
    ) {
        self.id = id
        self.speciesID = speciesID
        self.isShiny = isShiny
        self.capturedAt = capturedAt
        self.capturedAtTotalTokens = capturedAtTotalTokens
        self.evolutionSeed = evolutionSeed
        self.nickname = nickname
    }
}

/// El rival activo. `maxHP` se sortea al aparecer y no cambia.
public struct WildEncounter: Codable, Hashable, Sendable {
    public let speciesID: Int
    public let isShiny: Bool
    public let rarity: Rarity
    public let maxHP: Int
    public var currentHP: Int
    public let spawnedAt: Date

    public init(speciesID: Int, isShiny: Bool, rarity: Rarity, maxHP: Int, currentHP: Int? = nil, spawnedAt: Date = Date()) {
        self.speciesID = speciesID
        self.isShiny = isShiny
        self.rarity = rarity
        self.maxHP = max(1, maxHP)
        self.currentHP = min(max(0, currentHP ?? maxHP), max(1, maxHP))
        self.spawnedAt = spawnedAt
    }

    public var isFainted: Bool { currentHP <= 0 }
    public var hpFraction: Double { Double(currentHP) / Double(maxHP) }
}

/// Contabilidad de tokens. `monthly` se indexa por "YYYY-MM" en UTC.
public struct TokenLedger: Codable, Hashable, Sendable {
    public var total: Int = 0
    public var monthly: [String: Int] = [:]
    public var lastEventAt: Date?
    public var eventCount: Int = 0

    public static func monthKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public mutating func record(tokens: Int, at date: Date) {
        guard tokens > 0 else { return }
        total += tokens
        monthly[Self.monthKey(for: date), default: 0] += tokens
        eventCount += 1
        if let last = lastEventAt {
            lastEventAt = max(last, date)
        } else {
            lastEventAt = date
        }
    }

    public var currentMonth: Int { monthly[Self.monthKey(for: Date())] ?? 0 }
}

public struct GameSettings: Codable, Hashable, Sendable {
    public var countCacheTokens: Bool = false
    public var watchClaudeCodeTranscripts: Bool = true
    public var ingestServerEnabled: Bool = true
    public var ingestPort: UInt16 = 8317
}

/// Estado persistido completo. Cualquier cambio de forma requiere subir
/// `schemaVersion` y añadir migración en `GameStore`.
public struct GameState: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = GameState.currentSchemaVersion
    public var ledger = TokenLedger()
    public var box: [CapturedPokemon] = []
    public var activeCompanionID: UUID?
    public var encounter: WildEncounter?
    public var settings = GameSettings()
    /// IDs de eventos ya aplicados, en orden de llegada (ventana acotada).
    public var processedEventIDs: [String] = []
    public var lastCaptureSpeciesID: Int?

    public init() {}

    public var activeCompanion: CapturedPokemon? {
        guard let activeCompanionID else { return box.first }
        return box.first { $0.id == activeCompanionID } ?? box.first
    }

    public var hasStarter: Bool { !box.isEmpty }

    public mutating func markProcessed(_ eventID: String) {
        processedEventIDs.append(eventID)
        if processedEventIDs.count > GameRules.processedEventWindow {
            processedEventIDs.removeFirst(processedEventIDs.count - GameRules.processedEventWindow)
        }
    }
}
