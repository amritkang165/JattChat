# JattChat

JattChat is a native SwiftUI chatbot for iPhone that runs entirely on-device using Apple’s Foundation Models framework. It is a privacy-first demo and reference project for integrating `SystemLanguageModel` without external APIs, API keys, or cloud fallback.

## Features

- Native SwiftUI chat interface
- On-device responses using Apple Foundation Models
- No network calls, external services, or API keys
- SwiftData persistence for chat messages
- Apple Intelligence and model-readiness checks
- Loading state while generating responses
- Conversation reset support
- User and assistant message bubbles

## Screenshots

Add screenshots to `docs/screenshots/` and reference them here:

```markdown
![JattChat conversation](docs/screenshots/chat.png)
```

## Requirements

- macOS with Xcode 26.0
- Xcode 26.0 or later
- iOS 26.0 or later
- A compatible physical iPhone
- Apple Intelligence enabled on the device

The on-device model does not run in the iOS Simulator. A physical device is required.

## Technology Stack

- Swift
- SwiftUI
- SwiftData
- Combine
- FoundationModels
- Xcode 26.0
- iOS 26.0+

## Architecture

```text
JattChatApp
    |
    +-- SwiftData ModelContainer
    |
    +-- ContentView
            |
            +-- @Query ChatMessage records
            +-- MessageBubble views
            +-- User input and send controls
            +-- AIService.generateReply(to:)
                            |
                            +-- SystemLanguageModel.default
                            +-- LanguageModelSession
                            +-- session.respond(to:)
```

### Main Components

- `JattChatApp.swift` attaches the SwiftData model container.
- `ContentView.swift` loads messages, handles input, sends prompts, displays errors, and provides Reset.
- `AIService.swift` checks model availability and manages `LanguageModelSession`.
- `Message.swift` defines the SwiftData `ChatMessage` model.
- `MessageBubble.swift` renders user and assistant messages.

## FoundationModels Integration

JattChat uses Apple’s system language model through the `FoundationModels` framework.

### Availability

```swift
let model = SystemLanguageModel.default

switch model.availability {
case .available:
    // The model can be used.
case .unavailable(let reason):
    // Handle the unavailable reason.
}
```

The app handles these availability reasons:

- `.deviceNotEligible`
- `.appleIntelligenceNotEnabled`
- `.modelNotReady`

For `.modelNotReady`, keep the device connected to power and Wi-Fi so the system can prepare the required assets.

### Session Initialization

```swift
let session = LanguageModelSession(
    model: model,
    instructions: systemInstruction
)
```

The instructions define the assistant’s behavior, tone, and conversational context.

### Generating Responses

```swift
let response = try await session.respond(to: userMessage)
let text = response.content
```

`session.respond(to:)` returns `LanguageModelSession.Response<String>`. JattChat reads the generated text from `response.content` and stores it in SwiftData.

### Resetting Context

Resetting creates a fresh session:

```swift
session = LanguageModelSession(
    model: model,
    instructions: systemInstruction
)
```

The Reset action also removes persisted chat messages from SwiftData.

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/amritkang165/JattChat.git
cd JattChat
```

### 2. Open the Project

```bash
open JattChat.xcodeproj
```

### 3. Configure Xcode

1. Select the `JattChat` project and app target.
2. Set the deployment target to iOS 26.0 or later.
3. Link `FoundationModels.framework` under the target’s Frameworks, Libraries, and Embedded Content settings.
4. Select a compatible physical iPhone as the run destination.
5. Enable Apple Intelligence on the device.

### 4. Build and Run

Run from Xcode with:

```text
Product > Run
```

The app must run on a physical iPhone. The Simulator cannot execute the on-device model.

## Running and Offline Behavior

1. Launch JattChat on a compatible iPhone.
2. Wait for the model availability check to complete.
3. Enter a message and tap Send.
4. The user message is saved to SwiftData.
5. The prompt is sent to the on-device model.
6. The assistant response is saved and displayed.

JattChat makes no network calls and has no cloud fallback. When the model is available, inference runs locally on the device and requires no API key or backend.

An internet connection may still be required by the operating system while Apple Intelligence prepares or updates model assets.

## Troubleshooting

### `deviceNotEligible`

The connected device does not support the required Apple Intelligence features. Use a compatible physical iPhone.

### `appleIntelligenceNotEnabled`

Enable Apple Intelligence in the iPhone’s settings, then relaunch JattChat.

### `modelNotReady`

Keep the iPhone connected to power and Wi-Fi while the system prepares the model assets. Try again after preparation completes.

### Simulator Does Not Generate Responses

This integration requires a physical device. Select a compatible iPhone instead of an iOS Simulator.

### Old Placeholder Messages Appear

Use the Reset button to clear persisted messages and recreate the model session. You can also delete and reinstall the app to remove its local SwiftData store.

## Roadmap

- Stream responses using `streamResponse`
- Add tools and function calling
- Add structured outputs using `Generable` and `GenerationSchema`
- Restore model context from a persisted transcript
- Add message editing and regeneration
- Improve model capability and readiness diagnostics

## Privacy

JattChat is designed as a local, privacy-first reference application.

- No analytics
- No tracking
- No advertising SDKs
- No external AI APIs
- No application backend
- No cloud fallback
- No API keys
- Messages are stored locally using SwiftData

The system model is managed by Apple’s operating system and Foundation Models APIs. Consult Apple’s documentation and privacy policies for system-level model behavior.

## Performance Notes

- Sending is disabled while generation is in progress.
- Responses are generated asynchronously to keep the UI responsive.
- The app does not use timers to simulate response generation.
- SwiftData persists messages locally.
- Reset clears stored messages and creates a fresh session.
- Model availability is checked before generation.

## Repository Structure

```text
JattChat/
├── JattChat.xcodeproj/
│   ├── project.pbxproj
│   └── project.xcworkspace/
├── JattChat/
│   ├── AIService.swift
│   ├── ContentView.swift
│   ├── JattChatApp.swift
│   ├── Message.swift
│   ├── MessageBubble.swift
│   └── Assets.xcassets/
└── README.md
```

## Build and Push Changes

### Build from the Command Line

```bash
xcodebuild -list -project JattChat.xcodeproj

xcodebuild \
  -project JattChat.xcodeproj \
  -scheme JattChat \
  -destination 'generic/platform=iOS' \
  build
```

### Commit and Push with Git

```bash
git status
git add .
git commit -m "Describe the change"
git push origin main
```

### Using Xcode Source Control

1. Select `Source Control > Commit`.
2. Review the changed files.
3. Enter a commit message.
4. Commit the changes.
5. Select `Source Control > Push`.

## License

MIT or Apache-2.0 are recommended for this demo and reference project. Add a `LICENSE` file containing the complete text of the chosen license before publishing the project as open source.

Until a `LICENSE` file is added, the repository does not have a clearly declared open-source license.

## Acknowledgments

- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)

## Disclaimer

JattChat is an educational demo and reference implementation. Foundation Models availability, supported devices, APIs, and system behavior may change between SDK releases. Verify Apple’s current documentation when updating the project for a newer version of iOS or Xcode.
