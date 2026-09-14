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
    /// Fijaba la rama cuando la cadena bifurca. Desde que la rama la decide lo
    /// que se vence al evolucionar, solo se usa para desempatar cadenas sin
    /// regla de rama; se conserva porque está en `state.json`.
    public let evolutionSeed: UInt64
    /// Formas en las que ha ido evolucionando, en orden. Vacío = sigue siendo
    /// la especie con la que se capturó.
    ///
    /// Es un **hecho registrado**, no algo que se derive de los tokens: la rama
    /// se decidió con lo que vencía en ese momento, y tiene que seguir siendo
    /// la misma mañana.
    public var evolvedForms: [Int] = []
    /// Tokens ganados **mientras estaba equipado**. Es lo que le hace
    /// evolucionar, y solo crece: una evolución conseguida no se pierde al
    /// cambiar de compañero.
    public var tokensEarned: Int
    /// Si se muestra con su paleta shiny. Solo significa algo cuando
    /// `isShiny`: quien captura un shiny puede querer el look clásico.
    public var prefersShiny: Bool
    /// Salvajes vencidos llevándolo equipado.
    public var wildDefeats: Int
    /// Medallas ganadas llevándolo equipado.
    public var gymsWon: Int
    public var nickname: String?

    /// Cómo se dibuja: shiny solo si lo es y así lo quiere.
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
        nickname: String? = nil,
        evolvedForms: [Int] = []
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
        self.evolvedForms = evolvedForms
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
        evolvedForms = try container.decodeIfPresent([Int].self, forKey: .evolvedForms) ?? []
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

/// Cómo se escala el pixel art al agrandarlo. Entre el pixel duro y el
/// suavizado completo hay grados, y cuál gusta es cuestión de ojo.
public enum SpriteScaling: String, Codable, CaseIterable, Sendable {
    case pixel
    case medio
    case suave

    public var label: String {
        switch self {
        case .pixel: return "Pixel nítido"
        case .medio: return "Intermedio"
        case .suave: return "Suavizado"
        }
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
    public var spriteScaling: SpriteScaling = .medio
    /// Multiplicador de las miniaturas: HUD, rejillas de la caja, de la
    /// Pokédex y de medallas.
    public var spriteScale: Double = 1
    /// Multiplicador de la ficha, donde el sprite es el protagonista y se
    /// quiere más grande que en una rejilla.
    public var detailSpriteScale: Double = 1
    /// Rejilla o lista en la caja. Se persiste porque es una preferencia de
    /// lectura, no una consulta: quien quiere ver los números los quiere
    /// siempre.
    public var boxDensity: BoxDensity = .rejilla
    /// Secciones plegadas del popover, por título. Se persiste: plegar algo es
    /// decir "esto no me interesa ahora", y volver a abrir la app no lo cambia.
    public var collapsedSections: Set<String> = []
    /// Dónde estás cazando. El rival sale siempre de esta zona; `nil` solo
    /// mientras no has elegido, y entonces se resuelve a la más profunda que
    /// tengas abierta.
    public var currentZoneID: String?

    public init() {}

    /// El nombre viejo de `currentZoneID`, de cuando enfocar una zona era
    /// opcional. Va en su propio contenedor para no tener que escribir a mano
    /// las claves de todo lo demás.
    private enum LegacyKeys: String, CodingKey { case focusedZoneID }

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
        spriteScaling = try container.decodeIfPresent(SpriteScaling.self, forKey: .spriteScaling) ?? .medio
        let scale = try container.decodeIfPresent(Double.self, forKey: .spriteScale) ?? 1
        spriteScale = min(max(scale, GameRules.minimumSpriteScale), GameRules.maximumSpriteScale)
        let detail = try container.decodeIfPresent(Double.self, forKey: .detailSpriteScale) ?? 1
        detailSpriteScale = min(max(detail, GameRules.minimumSpriteScale), GameRules.maximumSpriteScale)
        boxDensity = try container.decodeIfPresent(BoxDensity.self, forKey: .boxDensity) ?? .rejilla
        collapsedSections = try container.decodeIfPresent(Set<String>.self, forKey: .collapsedSections) ?? []
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        currentZoneID = try container.decodeIfPresent(String.self, forKey: .currentZoneID)
            ?? legacy.decodeIfPresent(String.self, forKey: .focusedZoneID)
    }
}

/// Estado persistido completo. Cualquier cambio de forma requiere subir
/// `schemaVersion` y añadir migración en `GameStore`.
public struct GameState: Codable, Sendable {
    public static let currentSchemaVersion = 8

    public var schemaVersion: Int = GameState.currentSchemaVersion
    public var ledger = TokenLedger()
    public var box: [CapturedPokemon] = []
    public var activeCompanionID: UUID?
    public var encounter: WildEncounter?
    public var settings = GameSettings()
    public var gyms = GymProgress()
    public var milestones = MilestoneProgress()
    public var leagues = LeagueProgress()
    /// Veces que se ha vencido a cada línea evolutiva en libertad, con captura
    /// o sin ella. Clave: id de la forma base.
    public var familyDefeats: [Int: Int] = [:]
    /// Formas que **han sido tuyas** en algún momento, aunque el ejemplar ya
    /// haya evolucionado y no se vea. Es lo que hace que la Pokédex sea un
    /// registro y no una foto de la caja: sin esto, un Bulbasaur que llega a
    /// Venusaur borra a Ivysaur del contador, y como no se repiten líneas ese
    /// hueco no se podía volver a llenar nunca.
    public var registeredSpeciesIDs: Set<Int> = []
    /// IDs de eventos ya aplicados, en orden de llegada (ventana acotada).
    public var processedEventIDs: [String] = []
    public var lastCaptureSpeciesID: Int?
    /// Último salvaje vencido: es lo que decide la rama de la siguiente
    /// evolución, así que hay que recordarlo entre eventos.
    public var lastDefeatedSpeciesID: Int?
    /// Regiones que ya estaban abiertas cuando el requisito de Pokédex no
    /// existía. Quitarle a alguien un acceso que ya tenía es peor que el
    /// problema que arregla el requisito, así que se conserva.
    public var grandfatheredRegions: Set<String> = []
    /// Regiones cuya apertura ya se ha celebrado, para no repetir la fiesta.
    public var celebratedRegions: Set<String> = []

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
        milestones = try container.decodeIfPresent(MilestoneProgress.self, forKey: .milestones) ?? MilestoneProgress()
        leagues = try container.decodeIfPresent(LeagueProgress.self, forKey: .leagues) ?? LeagueProgress()
        familyDefeats = try container.decodeIfPresent([Int: Int].self, forKey: .familyDefeats) ?? [:]
        registeredSpeciesIDs = try container.decodeIfPresent(Set<Int>.self, forKey: .registeredSpeciesIDs) ?? []
        processedEventIDs = try container.decodeIfPresent([String].self, forKey: .processedEventIDs) ?? []
        lastCaptureSpeciesID = try container.decodeIfPresent(Int.self, forKey: .lastCaptureSpeciesID)
        lastDefeatedSpeciesID = try container.decodeIfPresent(Int.self, forKey: .lastDefeatedSpeciesID)
        grandfatheredRegions = try container.decodeIfPresent(Set<String>.self, forKey: .grandfatheredRegions) ?? []
        celebratedRegions = try container.decodeIfPresent(Set<String>.self, forKey: .celebratedRegions) ?? []
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
