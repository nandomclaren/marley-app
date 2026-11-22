import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Streams a Messages API request straight from the device with the user's own key.
public struct AnthropicStreamer: AIStreamer {
    public let apiKey: String
    public init(apiKey: String) { self.apiKey = apiKey }

    func request(_ body: Data) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        r.httpMethod = "POST"
        r.httpBody = body
        r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue(AI.apiVersion, forHTTPHeaderField: "anthropic-version")
        return r
    }

    public func stream(body: Data, onEvent: @escaping @Sendable (AIStreamEvent) -> Void) async throws -> AIResponse {
        #if canImport(Darwin)
        let (bytes, resp) = try await URLSession.shared.bytes(for: request(body))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            var data = Data()
            for try await b in bytes { data.append(b); if data.count > 20_000 { break } }
            let msg = (try? JSON.parse(data))?.objectValue?["error"]?.objectValue?["message"]?.stringValue ?? "HTTP \(status)"
            throw AIError.api(msg, status: status)
        }
        var acc = SSEAccumulator()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let ev = try acc.feed(line: line) { onEvent(ev) }
        }
        return try acc.finish()
        #else
        // Linux (tests only): no streaming bytes API; read the whole body.
        let (data, resp) = try await URLSession.shared.data(for: request(body))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AIError.api(String(decoding: data.prefix(300), as: UTF8.self), status: status) }
        var acc = SSEAccumulator()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") { if let ev = try acc.feed(line: String(line)) { onEvent(ev) } }
        return try acc.finish()
        #endif
    }
}
