import AVFoundation
import Foundation
import Observation
import Speech

/// On-device speech recognition for cook mode ("next", "back", "start timer", "repeat").
/// Audio never leaves the phone: `requiresOnDeviceRecognition` is set when supported, otherwise listening is refused.
@MainActor @Observable
final class VoiceController {
    enum State: Equatable { case off, listening, unavailable(String) }
    private(set) var state: State = .off
    private(set) var lastHeard: String = ""
    var onCommand: ((VoiceCommand) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var consumed = 0
    private var previous = ""
    private let synth = AVSpeechSynthesizer()
    private var restartTimer: Timer?

    var isListening: Bool { state == .listening }

    func toggle() { isListening ? stop() : start() }

    func start() {
        if AppConfig.isUITesting { state = .listening; return }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { self.state = .unavailable("Allow Speech Recognition in Settings to use voice."); return }
                AVAudioApplication.requestRecordPermission { ok in
                    Task { @MainActor in
                        guard ok else { self.state = .unavailable("Allow the microphone in Settings to use voice."); return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { state = .unavailable("Voice isn't available right now."); return }
        guard recognizer.supportsOnDeviceRecognition else { state = .unavailable("On-device voice isn't supported for this language."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = true
            req.contextualStrings = ["next", "back", "start timer", "repeat", "pause timer"]
            request = req; consumed = 0; previous = ""
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buf, _ in req?.append(buf) }
            engine.prepare(); try engine.start()
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.heard(result.bestTranscription.formattedString) }
                    if error != nil || result?.isFinal == true { self.recycle() }
                }
            }
            state = .listening
            // Recognition tasks end after ~1 min; restart periodically so listening is continuous.
            restartTimer?.invalidate()
            restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { _ in Task { @MainActor in self.recycle() } }
        } catch {
            state = .unavailable("Couldn't start the microphone.")
            teardown()
        }
    }

    /// Feed a transcript (used by the live recognizer and by UI tests).
    func heard(_ transcript: String) {
        // A new utterance (not a continuation of the previous partial result) restarts the consumed offset.
        if !transcript.hasPrefix(previous.prefix(consumed)) || transcript.count < consumed { consumed = 0 }
        previous = transcript
        lastHeard = transcript
        if let cmd = VoiceCommands.parse(transcript, after: consumed) {
            consumed = transcript.count
            Haptics.tap()
            onCommand?(cmd)
        }
    }

    private func recycle() {
        guard state == .listening else { return }
        teardown(); begin()
    }

    func stop() {
        restartTimer?.invalidate(); restartTimer = nil
        teardown()
        state = .off
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardown() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    func speak(_ text: String) {
        if AppConfig.isUITesting { lastHeard = "speaking: " + text; return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u)
    }
}
