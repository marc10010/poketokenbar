import Foundation

/// Lee el consumo real desde los transcripts JSONL de Claude Code
/// (`~/.claude/projects/**/*.jsonl`). Cero configuración: no intercepta nada,
/// solo sigue ficheros que la CLI ya escribe.
///
/// Los offsets se persisten para que un reinicio no reprocese el historial;
/// aun así cada evento lleva un id estable (requestId / message.id) y
/// `GameStore` es idempotente, de modo que un offset perdido no duplica daño.
public final class ClaudeCodeTranscriptSource: TokenSource {
    public let name = "Claude Code transcripts"

    private let root: URL
    private let offsetsURL: URL
    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "poketokenbar.transcripts")
    private var timer: DispatchSourceTimer?
    private var offsets: [String: UInt64] = [:]
    private var handler: ((UsageEvent) -> Void)?
    private var lastEventAt: Date?
    private var eventsSeen = 0

    public init(
        root: URL? = nil,
        offsetsURL: URL? = nil,
        pollInterval: TimeInterval = 2.0
    ) {
        self.root = root ?? AppPaths.claudeProjectsDirectory
        self.offsetsURL = offsetsURL ?? AppPaths.stateDirectory.appendingPathComponent("transcript-offsets.json")
        self.pollInterval = pollInterval
    }

    public var statusDescription: String {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return "sin transcripts en \(root.path)"
        }
        if let lastEventAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            return "\(eventsSeen) eventos · último \(formatter.localizedString(for: lastEventAt, relativeTo: Date()))"
        }
        return "a la escucha"
    }

    public func start(handler: @escaping (UsageEvent) -> Void) {
        self.handler = handler
        queue.async { [weak self] in
            guard let self else { return }
            self.loadOffsets()
            // Primer arranque: nos colocamos al final de cada fichero para no
            // volcar meses de historial de golpe sobre el rival actual.
            if self.offsets.isEmpty {
                for url in self.transcriptFiles() {
                    self.offsets[self.key(for: url)] = self.fileSize(url)
                }
                self.saveOffsets()
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in self?.saveOffsets() }
    }

    // MARK: - Ciclo de sondeo

    private func poll() {
        var dirty = false
        for url in transcriptFiles() {
            let size = fileSize(url)
            let key = key(for: url)
            let offset = offsets[key] ?? 0
            if size < offset {
                // Fichero truncado o rotado: volvemos a empezar por él.
                offsets[key] = 0
                dirty = true
            }
            guard size > (offsets[key] ?? 0) else { continue }
            let start = offsets[key] ?? 0
            if let (events, consumed) = readNewLines(at: url, from: start) {
                offsets[key] = start + consumed
                dirty = true
                for event in events { emit(event) }
            }
        }
        if dirty { saveOffsets() }
    }

    private func emit(_ event: UsageEvent) {
        lastEventAt = event.timestamp
        eventsSeen += 1
        handler?(event)
    }

    private func transcriptFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func fileSize(_ url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.uint64Value
    }

    private func key(for url: URL) -> String { url.path }

    /// Devuelve los eventos parseados y cuántos bytes se han consumido.
    /// Solo consumimos hasta el último salto de línea completo: si la CLI está
    /// escribiendo una línea a medias, la retomamos en el siguiente sondeo.
    private func readNewLines(at url: URL, from offset: UInt64) -> ([UsageEvent], UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], 0) }
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return ([], 0) }
        let complete = data[data.startIndex...lastNewline]
        let events = complete
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { Self.parseLine(Data($0), origin: url.lastPathComponent) }
        return (events, UInt64(complete.count))
    }

    /// Extrae `message.usage` de una línea de transcript. Ignora todo lo demás.
    public static func parseLine(_ line: Data, origin: String) -> UsageEvent? {
        guard !line.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let usageDict = message["usage"] as? [String: Any],
              let usageData = try? JSONSerialization.data(withJSONObject: usageDict),
              let usage = try? JSONDecoder().decode(AnthropicUsagePayload.self, from: usageData),
              !usage.isEmpty
        else { return nil }

        let messageID = message["id"] as? String
        let requestID = root["requestId"] as? String
        guard let id = requestID ?? messageID else { return nil }
        let model = (message["model"] as? String) ?? "unknown"
        let timestamp = (root["timestamp"] as? String).flatMap(Self.iso8601.date(from:)) ?? Date()

        return UsageEvent(
            id: "cc:\(id)",
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheCreationTokens: usage.cacheCreationTokens,
            cacheReadTokens: usage.cacheReadTokens,
            timestamp: timestamp,
            origin: "transcript:\(origin)"
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Offsets

    private func loadOffsets() {
        guard let data = try? Data(contentsOf: offsetsURL),
              let decoded = try? JSONDecoder().decode([String: UInt64].self, from: data)
        else { return }
        offsets = decoded
    }

    private func saveOffsets() {
        do {
            try FileManager.default.createDirectory(
                at: offsetsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(offsets)
            try data.write(to: offsetsURL, options: .atomic)
        } catch {
            NSLog("PokeTokenBar: no se pudieron guardar los offsets: \(error)")
        }
    }
}
