import Combine
import Foundation
import PokeTokenBarCore

/// Arranca las fuentes de tokens según los ajustes y las conecta al `GameStore`.
/// Añadir una fuente nueva es implementar `TokenSource` y registrarla aquí.
@MainActor
public final class TokenSourceCoordinator: ObservableObject {
    public struct SourceStatus: Hashable {
        public let name: String
        public let status: String
        public let healthy: Bool
    }

    @Published public private(set) var descriptions: [SourceStatus] = []

    private let store: GameStore
    private var sources: [TokenSource] = []
    private var pollTimer: Timer?

    public init(store: GameStore) {
        self.store = store
    }

    public func start() {
        let settings = store.state.settings
        if settings.watchClaudeCodeTranscripts {
            sources.append(ClaudeCodeTranscriptSource())
        }
        if settings.ingestServerEnabled {
            sources.append(IngestServer(port: AppPaths.ingestPortOverride ?? settings.ingestPort))
        }

        for source in sources {
            source.start { [weak self] event in
                // Las fuentes emiten desde sus propias colas; el estado vive en el main actor.
                Task { @MainActor in self?.store.ingest(event) }
            }
        }

        refreshStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for source in sources { source.stop() }
        sources.removeAll()
    }

    private func refreshStatus() {
        descriptions = sources.map { source in
            let status = source.statusDescription
            let healthy = !status.hasPrefix("error") && !status.hasPrefix("parado") && !status.hasPrefix("sin transcripts")
            return SourceStatus(name: source.name, status: status, healthy: healthy)
        }
    }
}
