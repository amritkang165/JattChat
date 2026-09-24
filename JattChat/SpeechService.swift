@preconcurrency import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class SpeechService: ObservableObject {
    enum State: Equatable {
        case idle
        case installingModel
        case ready
        case recording
        case stopping
        case interrupted
        case failed
    }

    enum SpeechServiceError: LocalizedError {
        case microphonePermissionDenied
        case speechPermissionDenied
        case unsupportedLocale
        case transcriberUnavailable
        case modelInstallationFailed(String)
        case audioSessionFailed(String)
        case microphoneUnavailable
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission was denied."
            case .speechPermissionDenied:
                return "Speech recognition permission was denied."
            case .unsupportedLocale:
                return "Speech transcription is not available for this language."
            case .transcriberUnavailable:
                return "On-device speech transcription is unavailable on this device."
            case .modelInstallationFailed(let message):
                return "Speech model installation failed: \(message)"
            case .audioSessionFailed(let message):
                return "Audio session failed: \(message)"
            case .microphoneUnavailable:
                return "No microphone is available."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalizedTranscript = ""
    @Published private(set) var error: SpeechServiceError?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioConverter: AVAudioConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var stopRequested = false

    var transcript: String {
        [finalizedTranscript, partialTranscript]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    deinit {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analysisTask?.cancel()
        resultsTask?.cancel()
        interruptionTask?.cancel()
    }

    func startTranscribing(locale: Locale = .current) async {
        guard state != .recording else { return }

        do {
            stopRequested = false
            error = nil
            partialTranscript = ""
            finalizedTranscript = ""
            state = .installingModel

            try await requestPermissions()

            guard SpeechTranscriber.isAvailable else {
                throw SpeechServiceError.transcriberUnavailable
            }

            guard let supportedLocale = await SpeechTranscriber.supportedLocale(
                equivalentTo: locale
            ) else {
                throw SpeechServiceError.unsupportedLocale
            }

            let transcriber = SpeechTranscriber(
                locale: supportedLocale,
                preset: .progressiveTranscription
            )

            if let installationRequest = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }

            guard !stopRequested else { throw CancellationError() }

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            ) else {
                throw SpeechServiceError.transcriberUnavailable
            }

            guard !stopRequested else { throw CancellationError() }

            try configureAudioSession()

            let (inputSequence, inputContinuation) =
                AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw SpeechServiceError.microphoneUnavailable
            }
            guard let audioConverter = AVAudioConverter(
                from: inputFormat,
                to: format
            ) else {
                throw SpeechServiceError.audioSessionFailed(
                    "The microphone format cannot be converted for speech analysis."
                )
            }

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.audioConverter = audioConverter
            self.inputContinuation = inputContinuation

            try installMicrophoneTap()

            analysisTask = Task { [weak self, analyzer] in
                do {
                    let lastAudioTime = try await analyzer.analyzeSequence(inputSequence)
                    if let lastAudioTime {
                        try await analyzer.finalizeAndFinish(through: lastAudioTime)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.fail(.transcriptionFailed(error.localizedDescription))
                }
            }

            resultsTask = Task { [weak self, transcriber] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        await MainActor.run {
                            if result.isFinal {
                                if !text.isEmpty {
                                    if !self!.finalizedTranscript.isEmpty {
                                        self!.finalizedTranscript += " "
                                    }
                                    self!.finalizedTranscript += text
                                }
                                self!.partialTranscript = ""
                            } else {
                                self!.partialTranscript = text
                            }
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.fail(.transcriptionFailed(error.localizedDescription))
                }
            }

            observeAudioInterruptions()
            try audioEngine.start()
            state = .recording
        } catch is CancellationError {
            state = .ready
        } catch let serviceError as SpeechServiceError {
            await fail(serviceError)
        } catch {
            await fail(.transcriptionFailed(error.localizedDescription))
        }
    }

    func stopTranscribing() async {
        if state == .installingModel {
            stopRequested = true
            state = .ready
            return
        }

        guard state == .recording || state == .interrupted else { return }

        state = .stopping
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        inputContinuation = nil

        do {
            if let analyzer {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        } catch is CancellationError {
            // Cancellation is expected when stopping an active session.
        } catch {
            self.error = .transcriptionFailed(error.localizedDescription)
        }

        analysisTask?.cancel()
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        audioConverter = nil

        interruptionTask?.cancel()
        interruptionTask = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )

        state = error == nil ? .ready : .failed
    }

    private func requestPermissions() async throws {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            throw SpeechServiceError.microphonePermissionDenied
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw SpeechServiceError.speechPermissionDenied
        }
    }

    private func configureAudioSession() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            throw SpeechServiceError.audioSessionFailed(error.localizedDescription)
        }
    }

    private func installMicrophoneTap() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw SpeechServiceError.microphoneUnavailable
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                guard let self, let audioConverter = self.audioConverter else { return }

                do {
                    let ratio = audioConverter.outputFormat.sampleRate /
                        audioConverter.inputFormat.sampleRate
                    let capacity = AVAudioFrameCount(
                        Double(buffer.frameLength) * ratio
                    ) + 1
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: audioConverter.outputFormat,
                        frameCapacity: capacity
                    ) else {
                        throw SpeechServiceError.microphoneUnavailable
                    }

                    var conversionError: NSError?
                    var suppliedInput = false
                    audioConverter.convert(
                        to: convertedBuffer,
                        error: &conversionError
                    ) { _, status in
                        if suppliedInput {
                            status.pointee = .noDataNow
                            return nil
                        }

                        suppliedInput = true
                        status.pointee = .haveData
                        return buffer
                    }

                    if let conversionError {
                        throw conversionError
                    }

                    self.inputContinuation?.yield(
                        AnalyzerInput(buffer: convertedBuffer)
                    )
                } catch {
                    await self.fail(.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }

    private func observeAudioInterruptions() {
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let self else { return }
                guard
                    let userInfo = notification.userInfo,
                    let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { continue }

                if type == .began {
                    self.audioEngine.pause()
                    self.state = .interrupted
                } else if type == .ended, self.state == .interrupted {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        try self.audioEngine.start()
                        self.state = .recording
                    } catch {
                        await self.fail(.audioSessionFailed(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func fail(_ error: SpeechServiceError) async {
        self.error = error
        if state == .recording || state == .interrupted {
            await stopTranscribing()
        } else {
            state = .failed
        }
    }
}
