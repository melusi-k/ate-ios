import Foundation

/// Hands-free cook-mode commands, parsed from a live speech transcript.
enum VoiceCommand: Equatable {
    case next, back, startTimer, pauseTimer, repeatStep, exit
}

enum VoiceCommands {
    private static let table: [(VoiceCommand, [String])] = [
        (.startTimer, ["start timer", "start the timer", "start a timer", "set timer", "set the timer", "timer start"]),
        (.pauseTimer, ["pause timer", "pause the timer", "stop timer", "stop the timer"]),
        (.repeatStep, ["repeat", "say again", "say that again", "read it", "read again", "what was that"]),
        (.back, ["go back", "previous", "back", "last step"]),
        (.next, ["next", "continue", "go on", "done", "forward"]),
        (.exit, ["exit cook mode", "stop cooking", "exit"]),
    ]

    /// The newest command in `transcript` that appears after `consumed` characters
    /// (speech results keep growing, so only the new tail is inspected).
    static func parse(_ transcript: String, after consumed: Int = 0) -> VoiceCommand? {
        let lower = transcript.lowercased()
        guard consumed < lower.count else { return nil }
        let tail = String(lower.dropFirst(consumed))
        var best: (VoiceCommand, String.Index)?
        for (cmd, phrases) in table {
            for p in phrases {
                guard let r = tail.range(of: p, options: .backwards) else { continue }
                // whole-word match
                let beforeOK = r.lowerBound == tail.startIndex || !tail[tail.index(before: r.lowerBound)].isLetter
                let afterOK = r.upperBound == tail.endIndex || !tail[r.upperBound].isLetter
                guard beforeOK && afterOK else { continue }
                if best == nil || r.lowerBound > best!.1 { best = (cmd, r.lowerBound) }
            }
        }
        return best?.0
    }
}
