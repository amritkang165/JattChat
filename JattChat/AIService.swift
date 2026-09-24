import Foundation
import Combine
import FoundationModels

@MainActor
final class AIService: ObservableObject {

    enum AIServiceError: LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason?)
        case sessionNotReady
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                if let reason {
                    return "On-device model unavailable: \(reason)"
                } else {
                    return "On-device model unavailable."
                }
            case .sessionNotReady:
                return "The language model session is not ready."
            case .generationFailed(let reason):
                return "Failed to generate a response: \(reason)"
            }
        }
    }

    // Availability has only .available and .unavailable(reason)
    @Published private(set) var availability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)
    @Published private(set) var isReady: Bool = false

    private var model: SystemLanguageModel?
    private var session: LanguageModelSession?

    // System instruction (persona) for JattChat.
    private let systemInstruction = """
    You are JattChat, a friendly, helpful, conversational AI assistant. Respond naturally, clearly, and concisely. Adapt to the user's language and tone, including Hinglish/Punjabi when appropriate. Use context from the ongoing conversation when answering follow-up questions.
    """

    init() {
        Task { [weak self] in
            await self?.initializeIfNeeded()
        }
    }

    func initializeIfNeeded() async {
        guard !isReady else { return }

        let model = SystemLanguageModel.default
        let availability = model.availability

        // Publish availability
        self.availability = availability

        switch availability {
        case .available:
            self.model = model
            // Create a session using the provided convenience initializer
            // that accepts model and string instructions.
            let session = LanguageModelSession(model: model, instructions: systemInstruction)
            self.session = session
            self.isReady = true

        case .unavailable:
            self.model = nil
            self.session = nil
            self.isReady = false
        }
    }

    func resetConversation() async {
        guard let model = model else {
            isReady = false
            return
        }
        // Recreate a fresh session to clear context
        let session = LanguageModelSession(model: model, instructions: systemInstruction)
        self.session = session
        self.isReady = true
    }

    func generateReply(to userMessage: String) async throws -> String {
        if !isReady {
            await initializeIfNeeded()
        }

        // Ensure the model is available on device (no cloud fallback)
        switch availability {
        case .available:
            break
        case .unavailable(let reason):
            throw AIServiceError.modelUnavailable(reason)
        }

        guard let session else {
            throw AIServiceError.sessionNotReady
        }

        do {
            // respond(to:) returns LanguageModelSession.Response<String>
            let response = try await session.respond(to: userMessage)
            return response.content
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
    }
}
