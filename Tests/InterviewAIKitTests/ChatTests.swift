import Foundation
import Testing
@testable import InterviewAIKit

@Test("Chat messages survive an encode and decode round trip")
func chatMessageRoundTrip() {
    let messages = [
        ChatMessage(role: "user", text: "What did we agree?"),
        ChatMessage(role: "assistant", text: "A band of 85 to 95.", sources: ["thermondo intro"], note: "Answered by the live model; the deep model was unavailable."),
    ]
    #expect(ChatMessage.decode(ChatMessage.encode(messages)) == messages)
    #expect(ChatMessage.decode("not json") == [])
    #expect(ChatMessage.decode("") == [])
}

@Test("The history window keeps the newest messages up to the count")
func chatWindowCount() {
    let messages = (1...8).map { ChatMessage(role: "user", text: "q\($0)") }
    let window = ChatPrompt.window(messages, maxMessages: 6, maxChars: 100_000)
    #expect(window.map(\.text) == ["q3", "q4", "q5", "q6", "q7", "q8"])
}

@Test("The history window cuts old turns past the character budget, never the newest")
func chatWindowChars() {
    let messages = [
        ChatMessage(role: "user", text: String(repeating: "a", count: 500)),
        ChatMessage(role: "assistant", text: String(repeating: "b", count: 500)),
        ChatMessage(role: "user", text: "latest"),
    ]
    let window = ChatPrompt.window(messages, maxMessages: 6, maxChars: 600)
    #expect(window.map(\.text) == [String(repeating: "b", count: 500), "latest"])
    let roomy = ChatPrompt.window(messages, maxMessages: 6, maxChars: 1_100)
    #expect(roomy.count == 3)
}

@Test("The turn prompt carries history, material and the question")
func chatUserMessage() {
    let history = [ChatMessage(role: "user", text: "Earlier question"), ChatMessage(role: "assistant", text: "Earlier answer")]
    let message = ChatPrompt.userMessage(history: history, material: "From meeting X:\nFacts", question: "And the timing?")
    #expect(message.contains("Conversation so far:\nUser: Earlier question\nAssistant: Earlier answer"))
    #expect(message.contains("Material:\nFrom meeting X:\nFacts"))
    #expect(message.hasSuffix("Question: And the timing?"))
    let cold = ChatPrompt.userMessage(history: [], material: "M", question: "Q")
    #expect(!cold.contains("Conversation so far"))
}
