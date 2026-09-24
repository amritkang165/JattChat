import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @State private var input = ""

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id) }
                    }
                }
            }

            HStack {
                TextField("Puchho kuch bhi...", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(input.isEmpty ? .gray : .blue)
                }
                .disabled(input.isEmpty)
            }
            .padding()
        }
    }

    func sendMessage() {
        modelContext.insert(ChatMessage(text: input, isUser: true))
        input = ""

        let reply = ChatMessage(text: "", isUser: false)
        modelContext.insert(reply)

        var tokens = ["Balle", " balle!", " Main", " soch", " riha", " si..."]
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            guard !tokens.isEmpty else { timer.invalidate(); return }
            let token = tokens.removeFirst()
            reply.text += token
        }
    }
}
