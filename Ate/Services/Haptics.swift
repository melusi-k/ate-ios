import UIKit
import CoreHaptics
import AVFoundation

/// Haptics + the bundled 3-tone timer chime (`ate-chime.wav`, E5–G5–C6).
@MainActor
enum Haptics {
    private static var engine: CHHapticEngine?
    private static var player: AVAudioPlayer?

    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func step() { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8) }
    static func toggle() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }

    /// Three taps in time with the chime, then a short rumble.
    static func timerDone() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { success(); return }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.resetHandler = { Task { @MainActor in try? engine?.start() } }
            }
            try engine?.start()
            var events: [CHHapticEvent] = [0.0, 0.22, 0.44].map { t in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)], relativeTime: t)
            }
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)], relativeTime: 0.66, duration: 0.45))
            try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: 0)
        } catch { success() }
    }

    static var chimeURL: URL? { Bundle.main.url(forResource: "ate-chime", withExtension: "wav") }

    static func chime() {
        guard let url = chimeURL else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.9
        player?.play()
    }
}
