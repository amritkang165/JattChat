import Foundation
import SwiftData

@Model
final class ChatMessage {
    var text: String
    var isUser: Bool
    var timestamp: Date

    init(text: String, isUser: Bool, timestamp: Date = .now) {
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}
