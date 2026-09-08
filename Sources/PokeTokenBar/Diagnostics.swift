import Foundation
import PokeTokenBarCore

/// Log de arranque en `<stateDir>/diagnostics.log`. Una app de barra de menú no
/// tiene ventana donde mostrar un error y stderr se pierde al lanzarla con
/// `open`, así que dejamos rastro en disco.
enum Diagnostics {
    private static let url = AppPaths.stateDirectory.appendingPathComponent("diagnostics.log")
    private static let queue = DispatchQueue(label: "poketokenbar.diagnostics")

    static func append(_ line: String) {
        let stamped = "[" + ISO8601DateFormatter().string(from: Date()) + "] " + line
        queue.async {
            let payload = Data((stamped + "\n").utf8)
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: payload)
                } else {
                    try payload.write(to: url, options: .atomic)
                }
            } catch {
                NSLog("PokeTokenBar: no se pudo escribir diagnostics.log: \(error)")
            }
        }
    }
}
