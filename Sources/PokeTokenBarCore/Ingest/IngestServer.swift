import Foundation
import Network

/// Servidor HTTP mínimo en 127.0.0.1 para que cualquier proceso pueda reportar
/// consumo: `POST /usage` con el bloque `usage` de la respuesta de Anthropic.
///
/// Escucha SOLO en loopback y no acepta credenciales ni reenvía tráfico: el
/// proxy que habla con la API vive fuera (ver `tools/anthropic-proxy.mjs`), así
/// la app nunca ve la API key.
public final class IngestServer: TokenSource {
    public let name = "Ingest HTTP local"

    private let port: UInt16
    private let queue = DispatchQueue(label: "poketokenbar.ingest")
    private var listener: NWListener?
    private var handler: ((UsageEvent) -> Void)?
    private var accepted = 0
    private var lastError: String?

    public init(port: UInt16 = 8317) {
        self.port = port
    }

    public var statusDescription: String {
        if let lastError { return "error: \(lastError)" }
        guard listener != nil else { return "parado" }
        return "127.0.0.1:\(port) · \(accepted) reportes"
    }

    public func start(handler: @escaping (UsageEvent) -> Void) {
        self.handler = handler
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .init(rawValue: port)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.lastError = error.localizedDescription
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            NSLog("PokeTokenBar: el servidor de ingest no arrancó: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if error != nil {
                connection.cancel()
                return
            }
            if let request = HTTPRequest(raw: buffer) {
                self.respond(to: request, on: connection)
                return
            }
            if isComplete || buffer.count > 1 << 20 {
                self.send(status: "400 Bad Request", body: #"{"error":"petición ilegible"}"#, on: connection)
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            send(status: "200 OK", body: #"{"ok":true}"#, on: connection)
        case ("POST", "/usage"):
            guard let event = Self.event(from: request.body) else {
                send(status: "422 Unprocessable Entity", body: #"{"error":"falta usage con input_tokens/output_tokens"}"#, on: connection)
                return
            }
            accepted += 1
            handler?(event)
            send(status: "202 Accepted", body: #"{"accepted":true}"#, on: connection)
        default:
            send(status: "404 Not Found", body: #"{"error":"ruta desconocida"}"#, on: connection)
        }
    }

    /// Acepta tanto `{"usage": {...}}` como el bloque `usage` plano, con
    /// `id`/`model`/`timestamp` opcionales al mismo nivel.
    public static func event(from body: Data) -> UsageEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let usageDict = (root["usage"] as? [String: Any]) ?? root
        guard let usageData = try? JSONSerialization.data(withJSONObject: usageDict),
              let usage = try? JSONDecoder().decode(AnthropicUsagePayload.self, from: usageData),
              !usage.isEmpty
        else { return nil }

        let id = (root["id"] as? String) ?? (root["request_id"] as? String) ?? UUID().uuidString
        let model = (root["model"] as? String) ?? "unknown"
        let timestamp = (root["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return UsageEvent(
            id: "ingest:\(id)",
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheCreationTokens: usage.cacheCreationTokens,
            cacheReadTokens: usage.cacheReadTokens,
            timestamp: timestamp,
            origin: "ingest"
        )
    }

    private func send(status: String, body: String, on connection: NWConnection) {
        let payload = Data(body.utf8)
        let head = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        \r\n
        """
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Parser HTTP suficiente para este caso: request-line, Content-Length y cuerpo.
public struct HTTPRequest {
    public let method: String
    public let path: String
    public let body: Data

    public init?(raw: Data) {
        guard let separator = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = raw[raw.startIndex..<separator.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: true)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        path = String(parts[1].split(separator: "?").first ?? "")

        let contentLength = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let available = raw[separator.upperBound...]
        guard available.count >= contentLength else { return nil }
        body = Data(available.prefix(contentLength))
    }
}
