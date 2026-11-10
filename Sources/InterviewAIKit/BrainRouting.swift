import Foundation

/// Which model answers, per task. Live answers in a call stay on the
/// fast model; the thinking done outside a call (the Ask page,
/// meeting summaries and follow-ups, Profile generation) can use a
/// bigger Deep model when Dual-Brain is on. Pure value logic, so the
/// routing is testable without a provider.
public enum BrainTask: Sendable {
    case live
    case deep
}

public enum BrainRouting {
    /// The deep default: a local 8B, strong enough to write a summary
    /// worth reading, small enough for a 16 GB Mac.
    public static let defaultDeepModel = "llama3.1:8b"

    /// The config a task runs on. The Deep model swaps only the model
    /// name: same provider, same endpoint, same key. Toggle off, an
    /// empty deep name, or the deep name equal to the live one all
    /// resolve to the live config untouched, so an install without
    /// Dual-Brain behaves exactly as before.
    public static func resolve(task: BrainTask, dualBrain: Bool, live: BrainConfig, deepModel: String) -> BrainConfig {
        guard task == .deep, dualBrain else { return live }
        let deep = deepModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deep.isEmpty, deep != live.model else { return live }
        var config = live
        config.model = deep
        return config
    }

    /// Whether a resolved config is actually the Deep model.
    public static func isDeep(_ config: BrainConfig, live: BrainConfig) -> Bool {
        config.model != live.model
    }

    /// Deep requests tell Ollama to keep the big model loaded for
    /// five minutes, then let it leave memory: the model must not sit
    /// in RAM on a 16 GB Mac. Anything that resolves to the live
    /// model sends nothing and keeps the provider default.
    public static func keepAlive(task: BrainTask, dualBrain: Bool, live: BrainConfig, deepModel: String) -> String? {
        let resolved = resolve(task: task, dualBrain: dualBrain, live: live, deepModel: deepModel)
        return isDeep(resolved, live: live) ? "5m" : nil
    }
}

/// Serializes Deep work: one Deep job at a time, so two big-model
/// jobs never load or run side by side. Each job waits for the one
/// before it to finish, whatever it returned.
public actor DeepWorkQueue {
    public static let shared = DeepWorkQueue()

    private var tail: Task<Void, Never>?

    public init() {}

    public func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let job = Task {
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await job.value }
        return try await job.value
    }
}
