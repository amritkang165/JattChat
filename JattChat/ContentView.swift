import SwiftUI
import SwiftData
import FoundationModels

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]

    @State private var input = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @StateObject private var ai = AIService()

    var body: some View {
        VStack {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if isGenerating {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack {
                TextField("Puchho kuch bhi...", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .disabled(isGenerating)

                Button(action: { Task { await sendMessage() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
            }
            .padding()
        }
        .task {
            await ai.initializeIfNeeded()
            switch ai.availability {
            case .available:
                break
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    errorMessage = "This device doesn’t support Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    errorMessage = "Please enable Apple Intelligence in Settings."
                case .modelNotReady:
                    errorMessage = "On-device model not ready yet. Keep the phone on power and Wi‑Fi."
                }
            }
            // Optional: log availability to help debug
            print("Availability:", String(describing: ai.availability))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    Task { await resetAll() }
                }
            }
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    @MainActor
    private func insertMessage(_ text: String, isUser: Bool) -> ChatMessage {
        let message = ChatMessage(text: text, isUser: isUser)
        modelContext.insert(message)
        return message
    }

    private func sendMessage() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isGenerating else { return }

        errorMessage = nil
        isGenerating = true

        // 1) Save user message
        _ = insertMessage(trimmed, isUser: true)

        // 2) Clear input
        input = ""

        // 3) Ask on-device model
        do {
            print("Calling model with:", trimmed)
            let replyText = try await ai.generateReply(to: trimmed)
            print("Model replied:", replyText)
            _ = insertMessage(replyText, isUser: false)
        } catch {
            if let aiErr = error as? AIService.AIServiceError {
                errorMessage = aiErr.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isGenerating = false
    }

    @MainActor
    private func deleteAllMessages() {
        for msg in messages {
            modelContext.delete(msg)
        }
    }

    private func resetAll() async {
        await MainActor.run {
            deleteAllMessages()
            errorMessage = nil
            input = ""
        }
        await ai.resetConversation()
        print("Reset complete.")
    }
}
