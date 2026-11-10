import Foundation
import Security

/// Where answers come from. Local Ollama needs no key and no account.
/// An OpenAI-compatible endpoint uses the user's own key, from the
/// Keychain. There is no InterviewAI server, plan, or quota.
public struct BrainConfig: Equatable, Sendable {
    public enum Kind: String, Sendable { case ollama, openAICompatible }
    public var kind: Kind
    public var baseURL: String
    public var model: String
    public var visionModel: Bool

    public init(kind: Kind, baseURL: String, model: String, visionModel: Bool = false) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.visionModel = visionModel
    }

    public static let localDefault = BrainConfig(kind: .ollama, baseURL: "http://localhost:11434", model: "llama3.2:1b")
}

public enum BrainError: Error, LocalizedError {
    case badURL(String)
    case http(Int, String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badURL(let url): "The provider address is not a valid URL: \(url)"
        case .http(let code, let body): "The provider answered \(code). \(body.prefix(200))"
        case .empty: "The provider sent no answer."
        }
    }
}

public enum Brain {
    /// Stream the answer as text pieces. `imagePNG` is a screenshot in
    /// base64 when the user attached one and the model can read images.
    /// `maxTokens` caps the reply: 400 keeps a spoken answer speakable,
    /// but a summary needs room to be worth reading, so callers that
    /// write documents pass more.
    public static func stream(config: BrainConfig, apiKey: String, system: String, user: String, imageBase64: String?, maxTokens: Int = 400, keepAlive: String? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(config: config, apiKey: apiKey, system: system, user: user, imageBase64: imageBase64, maxTokens: maxTokens, keepAlive: keepAlive)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 400 { break } }
                        throw BrainError.http(http.statusCode, body)
                    }
                    var produced = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let piece = extract(line: line, kind: config.kind), !piece.isEmpty {
                            produced = true
                            continuation.yield(piece)
                        }
                    }
                    if !produced { throw BrainError.empty }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One full answer, collected. Used for summaries and connection tests.
    public static func complete(config: BrainConfig, apiKey: String, system: String, user: String, maxTokens: Int = 400, keepAlive: String? = nil) async throws -> String {
        var out = ""
        for try await piece in stream(config: config, apiKey: apiKey, system: system, user: user, imageBase64: nil, maxTokens: maxTokens, keepAlive: keepAlive) {
            out += piece
        }
        return out
    }

    /// Pull the text piece out of one streamed line, per provider shape.
    public static func extract(line: String, kind: BrainConfig.Kind) -> String? {
        var payload = line
        if kind == .openAICompatible {
            guard line.hasPrefix("data:") else { return nil }
            payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" || payload.isEmpty { return nil }
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch kind {
        case .ollama:
            let message = json["message"] as? [String: Any]
            return message?["content"] as? String
        case .openAICompatible:
            let choices = json["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            return delta?["content"] as? String
        }
    }

    private static func makeRequest(config: BrainConfig, apiKey: String, system: String, user: String, imageBase64: String?, maxTokens: Int = 400, keepAlive: String? = nil) throws -> URLRequest {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        let path = config.kind == .ollama ? "/api/chat" : "/v1/chat/completions"
        guard let url = URL(string: base + path) else { throw BrainError.badURL(config.baseURL) }

        var messages: [[String: Any]] = []
        switch config.kind {
        case .ollama:
            messages.append(["role": "system", "content": system])
            var userMessage: [String: Any] = ["role": "user", "content": user]
            if let imageBase64, config.visionModel { userMessage["images"] = [imageBase64] }
            messages.append(userMessage)
        case .openAICompatible:
            messages.append(["role": "system", "content": system])
            if let imageBase64, config.visionModel {
                messages.append(["role": "user", "content": [
                    ["type": "text", "text": user],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(imageBase64)"]],
                ] as [[String: Any]]])
            } else {
                messages.append(["role": "user", "content": user])
            }
        }

        // Generation options matter as much as the model. Without a
        // num_ctx, Ollama silently truncates the prompt to its 2048
        // token default, and the system prompt plus most of the
        // context never reach the model: answers come out ungrounded
        // and generic. A low temperature keeps answers factual, and a
        // predict cap keeps them speakable instead of rambling.
        var body: [String: Any] = ["model": config.model, "stream": true, "messages": messages]
        switch config.kind {
        case .ollama:
            body["options"] = ["temperature": 0.3, "num_ctx": 8192, "num_predict": maxTokens]
            // Deep work passes a short keep-alive so the big model
            // leaves memory soon after the job; live work sends
            // nothing and keeps Ollama's default.
            if let keepAlive { body["keep_alive"] = keepAlive }
        case .openAICompatible:
            body["temperature"] = 0.3
            body["max_tokens"] = maxTokens
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.kind == .openAICompatible, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        return request
    }
}

/// The user's provider key, in the Keychain only.
public enum KeychainStore {
    private static let service = "com.nilseffmert.interviewai"

    /// Returns false when the Keychain refused the write, so the
    /// caller can say so instead of claiming a save that never
    /// landed (a rebuilt app can lose access to its own items).
    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func get(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
