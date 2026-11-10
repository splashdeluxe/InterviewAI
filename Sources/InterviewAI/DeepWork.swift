import Foundation
import InterviewAIKit

/// One Deep job, start to finish: on the Deep model when Dual-Brain
/// is on, one job at a time through the queue, with the live model as
/// the fallback. A fallback is reported in the outcome, never hidden
/// and never a dead end: the job gets an answer from somewhere, or
/// the live model's own error, which is the error the user would
/// have seen without Dual-Brain.
enum DeepWork {
    struct Outcome {
        let text: String
        let fellBack: Bool
    }

    /// A whole answer, collected: summaries, follow-ups, Profile
    /// generation. If the Deep request fails, the whole job retries
    /// on the live model.
    static func complete(system: String, user: String, maxTokens: Int = 400) async throws -> Outcome {
        let live = ProviderSettings.config()
        let deep = ProviderSettings.config(for: .deep)
        let apiKey = ProviderSettings.apiKey
        guard BrainRouting.isDeep(deep, live: live) else {
            let text = try await Brain.complete(config: live, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens)
            return Outcome(text: text, fellBack: false)
        }
        return try await DeepWorkQueue.shared.run {
            do {
                let text = try await Brain.complete(config: deep, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens, keepAlive: "5m")
                return Outcome(text: text, fellBack: false)
            } catch {
                let text = try await Brain.complete(config: live, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens)
                return Outcome(text: text, fellBack: true)
            }
        }
    }

    /// A streamed answer: the Ask page. The fallback only takes over
    /// when the Deep model fails before its first piece; a failure
    /// mid-answer surfaces as an error, like any other stream.
    static func stream(system: String, user: String, onFallback: @escaping @MainActor () -> Void) -> AsyncThrowingStream<String, Error> {
        let live = ProviderSettings.config()
        let deep = ProviderSettings.config(for: .deep)
        let apiKey = ProviderSettings.apiKey
        guard BrainRouting.isDeep(deep, live: live) else {
            return Brain.stream(config: live, apiKey: apiKey, system: system, user: user, imageBase64: nil)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await DeepWorkQueue.shared.run {
                        var produced = false
                        do {
                            for try await piece in Brain.stream(config: deep, apiKey: apiKey, system: system, user: user, imageBase64: nil, keepAlive: "5m") {
                                produced = true
                                continuation.yield(piece)
                            }
                        } catch {
                            if produced { throw error }
                            await MainActor.run(body: onFallback)
                            for try await piece in Brain.stream(config: live, apiKey: apiKey, system: system, user: user, imageBase64: nil) {
                                continuation.yield(piece)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
