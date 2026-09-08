import Foundation

/// Rutas y overrides por entorno. Existen para poder ejecutar la app contra un
/// estado desechable (pruebas manuales, demos) sin tocar la partida real.
public enum AppPaths {
    public static let stateDirectoryOverrideKey = "POKETOKENBAR_STATE_DIR"
    public static let claudeProjectsOverrideKey = "POKETOKENBAR_CLAUDE_PROJECTS"
    public static let ingestPortOverrideKey = "POKETOKENBAR_INGEST_PORT"

    public static var stateDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[stateDirectoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("PokeTokenBar", isDirectory: true)
    }

    public static var claudeProjectsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[claudeProjectsOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public static var ingestPortOverride: UInt16? {
        guard let raw = ProcessInfo.processInfo.environment[ingestPortOverrideKey] else { return nil }
        return UInt16(raw)
    }
}
