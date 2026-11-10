import Foundation
import Testing
@testable import InterviewAIKit

private let liveConfig = BrainConfig(kind: .ollama, baseURL: "http://localhost:11434", model: "llama3.2:1b", visionModel: true)

@Test("Live tasks always resolve to the live model")
func routingLiveTask() {
    #expect(BrainRouting.resolve(task: .live, dualBrain: true, live: liveConfig, deepModel: "llama3.1:8b") == liveConfig)
    #expect(BrainRouting.resolve(task: .live, dualBrain: false, live: liveConfig, deepModel: "llama3.1:8b") == liveConfig)
}

@Test("Deep tasks stay on the live model while Dual-Brain is off")
func routingDeepToggleOff() {
    #expect(BrainRouting.resolve(task: .deep, dualBrain: false, live: liveConfig, deepModel: "llama3.1:8b") == liveConfig)
    #expect(BrainRouting.keepAlive(task: .deep, dualBrain: false, live: liveConfig, deepModel: "llama3.1:8b") == nil)
}

@Test("Deep tasks swap only the model name when Dual-Brain is on")
func routingDeepToggleOn() {
    let resolved = BrainRouting.resolve(task: .deep, dualBrain: true, live: liveConfig, deepModel: "llama3.1:8b")
    #expect(resolved.model == "llama3.1:8b")
    #expect(resolved.kind == liveConfig.kind)
    #expect(resolved.baseURL == liveConfig.baseURL)
    #expect(resolved.visionModel == liveConfig.visionModel)
    #expect(BrainRouting.isDeep(resolved, live: liveConfig))
    #expect(BrainRouting.keepAlive(task: .deep, dualBrain: true, live: liveConfig, deepModel: "llama3.1:8b") == "5m")
}

@Test("An empty or matching deep name falls back to the live config")
func routingDeepUnset() {
    #expect(BrainRouting.resolve(task: .deep, dualBrain: true, live: liveConfig, deepModel: "") == liveConfig)
    #expect(BrainRouting.resolve(task: .deep, dualBrain: true, live: liveConfig, deepModel: "  ") == liveConfig)
    #expect(BrainRouting.resolve(task: .deep, dualBrain: true, live: liveConfig, deepModel: "llama3.2:1b") == liveConfig)
    #expect(BrainRouting.keepAlive(task: .deep, dualBrain: true, live: liveConfig, deepModel: "") == nil)
    #expect(!BrainRouting.isDeep(liveConfig, live: liveConfig))
}

@Test("Deep work runs one job at a time")
func deepQueueSerializes() async {
    actor Log {
        var entries: [String] = []
        func add(_ entry: String) { entries.append(entry) }
    }
    let queue = DeepWorkQueue()
    let log = Log()
    await withTaskGroup(of: Void.self) { group in
        for index in 1...3 {
            group.addTask {
                try? await queue.run {
                    await log.add("start-\(index)")
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    await log.add("end-\(index)")
                }
            }
        }
    }
    let entries = await log.entries
    #expect(entries.count == 6)
    // Serialized: every start is followed at once by its own end.
    for position in stride(from: 0, to: entries.count, by: 2) {
        let start = entries[position]
        #expect(start.hasPrefix("start-"))
        #expect(entries[position + 1] == "end-" + start.dropFirst("start-".count))
    }
}
