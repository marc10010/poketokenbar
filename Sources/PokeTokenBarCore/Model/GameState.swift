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
    /// Tokens ganados **mientras estaba equipado**. Es lo que le hace
    /// evolucionar, y solo crece: una evolución conseguida no se pierde al
    /// cambiar de compañero.
    public var tokensEarned: Int
    /// Si se muestra con su paleta variocolor. Solo significa algo cuando
    /// `isShiny`: quien captura un variocolor puede querer el look clásico.
    public var prefersShiny: Bool
    /// Salvajes vencidos llevándolo equipado.
    public var wildDefeats: Int
    /// Medallas ganadas llevándolo equipado.
    public var gymsWon: Int
    public var nickname: String?

    /// Cómo se dibuja: variocolor solo si lo es y así lo quiere.
    public var displaysShiny: Bool { isShiny && prefersShiny }

    public init(
        id: UUID = UUID(),
        speciesID: Int,
        isShiny: Bool,
        capturedAt: Date = Date(),
        capturedAtTotalTokens: Int,
        evolutionSeed: UInt64 = UInt64.random(in: 0..<UInt64.max),
        tokensEarned: Int = 0,
        prefersShiny: Bool = true,
        wildDefeats: Int = 0,
        gymsWon: Int = 0,
        nickname: String? = nil
    ) {
        self.id = id
        self.speciesID = speciesID
        self.isShiny = isShiny
        self.capturedAt = capturedAt
        self.capturedAtTotalTokens = capturedAtTotalTokens
        self.evolutionSeed = evolutionSeed
        self.tokensEarned = tokensEarned
        self.prefersShiny = prefersShiny
        self.wildDefeats = wildDefeats
        self.gymsWon = gymsWon
        self.nickname = nickname
    }

    /// Decodificación tolerante: los ficheros de la versión anterior no traen
    /// `tokensEarned` (la migración de `StateFileStore` los rellena).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        speciesID = try container.decode(Int.self, forKey: .speciesID)
        isShiny = try container.decode(Bool.self, forKey: .isShiny)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        capturedAtTotalTokens = try container.decode(Int.self, forKey: .capturedAtTotalTokens)
        evolutionSeed = try container.decode(UInt64.self, forKey: .evolutionSeed)
        tokensEarned = try container.decodeIfPresent(Int.self, forKey: .tokensEarned) ?? 0
        prefersShiny = try container.decodeIfPresent(Bool.self, forKey: .prefersShiny) ?? true
        wildDefeats = try container.decodeIfPresent(Int.self, forKey: .wildDefeats) ?? 0
        gymsWon = try container.decodeIfPresent(Int.self, forKey: .gymsWon) ?? 0
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
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

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        monthly = try container.decodeIfPresent([String: Int].self, forKey: .monthly) ?? [:]
        lastEventAt = try container.decodeIfPresent(Date.self, forKey: .lastEventAt)
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0
    }

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

/// Esquina de la pantalla donde se ancla el HUD flotante.
public enum HUDCorner: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var label: String {
        switch self {
        case .topLeft: return "Arriba izq."
        case .topRight: return "Arriba der."
        case .bottomLeft: return "Abajo izq."
        case .bottomRight: return "Abajo der."
        }
    }
}

/// Posición libre del HUD en coordenadas globales de pantalla, cuando el
/// usuario lo ha arrastrado fuera de su esquina.
public struct HUDOrigin: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Tamaño del HUD cuando el usuario lo ha redimensionado a mano.
public struct HUDSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct GameSettings: Codable, Hashable, Sendable {
    public var countCacheTokens: Bool = false
    public var watchClaudeCodeTranscripts: Bool = true
    public var ingestServerEnabled: Bool = true
    public var ingestPort: UInt16 = 8317
    public var hudEnabled: Bool = true
    public var hudCorner: HUDCorner = .topRight
    public var hudOpacity: Double = 0.9
    /// Bloqueado = click-through: se ve pero no recibe clics ni se puede mover.
    public var hudLocked: Bool = false
    /// `nil` = anclado a `hudCorner` y replicado en todas las pantallas.
    public var hudFreeOrigin: HUDOrigin?
    /// `nil` = tamaño compacto (solo el combate).
    public var hudSize: HUDSize?
    /// Multiplicador de daño por tipos (agua > fuego y compañía).
    public var typeEffectivenessEnabled: Bool = true

    public init() {}

    /// Decodificación tolerante: un `state.json` escrito por una versión
    /// anterior no tiene las claves nuevas y debe seguir cargando.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countCacheTokens = try container.decodeIfPresent(Bool.self, forKey: .countCacheTokens) ?? false
        watchClaudeCodeTranscripts = try container.decodeIfPresent(Bool.self, forKey: .watchClaudeCodeTranscripts) ?? true
        ingestServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .ingestServerEnabled) ?? true
        ingestPort = try container.decodeIfPresent(UInt16.self, forKey: .ingestPort) ?? 8317
        hudEnabled = try container.decodeIfPresent(Bool.self, forKey: .hudEnabled) ?? true
        hudCorner = try container.decodeIfPresent(HUDCorner.self, forKey: .hudCorner) ?? .topRight
        hudOpacity = try container.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? 0.9
        hudLocked = try container.decodeIfPresent(Bool.self, forKey: .hudLocked) ?? false
        hudFreeOrigin = try container.decodeIfPresent(HUDOrigin.self, forKey: .hudFreeOrigin)
        hudSize = try container.decodeIfPresent(HUDSize.self, forKey: .hudSize)
        typeEffectivenessEnabled = try container.decodeIfPresent(Bool.self, forKey: .typeEffectivenessEnabled) ?? true
    }
}

/// Estado persistido completo. Cualquier cambio de forma requiere subir
/// `schemaVersion` y añadir migración en `GameStore`.
public struct GameState: Codable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int = GameState.currentSchemaVersion
    public var ledger = TokenLedger()
    public var box: [CapturedPokemon] = []
    public var activeCompanionID: UUID?
    public var encounter: WildEncounter?
    public var settings = GameSettings()
    public var gyms = GymProgress()
    /// Veces que se ha vencido a cada línea evolutiva en libertad, con captura
    /// o sin ella. Clave: id de la forma base.
    public var familyDefeats: [Int: Int] = [:]
    /// IDs de eventos ya aplicados, en orden de llegada (ventana acotada).
    public var processedEventIDs: [String] = []
    public var lastCaptureSpeciesID: Int?

    public init() {}

    /// Decodificación tolerante por el mismo motivo que en `GameSettings`: si
    /// un fichero antiguo no trae una clave, se usa el valor por defecto en vez
    /// de tirar el estado entero a cuarentena.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ledger = try container.decodeIfPresent(TokenLedger.self, forKey: .ledger) ?? TokenLedger()
        box = try container.decodeIfPresent([CapturedPokemon].self, forKey: .box) ?? []
        activeCompanionID = try container.decodeIfPresent(UUID.self, forKey: .activeCompanionID)
        encounter = try container.decodeIfPresent(WildEncounter.self, forKey: .encounter)
        settings = try container.decodeIfPresent(GameSettings.self, forKey: .settings) ?? GameSettings()
        gyms = try container.decodeIfPresent(GymProgress.self, forKey: .gyms) ?? GymProgress()
        familyDefeats = try container.decodeIfPresent([Int: Int].self, forKey: .familyDefeats) ?? [:]
        processedEventIDs = try container.decodeIfPresent([String].self, forKey: .processedEventIDs) ?? []
        lastCaptureSpeciesID = try container.decodeIfPresent(Int.self, forKey: .lastCaptureSpeciesID)
    }

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
