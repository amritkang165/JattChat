import SwiftUI
import SwiftData

@main
struct JattChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ChatMessage.self)
    }
}
