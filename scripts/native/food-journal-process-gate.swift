import Foundation
import Darwin

@MainActor
protocol ClearAllWriterGating {
    func acquireResetGate() throws
    func validateResetGate() throws
    func releaseResetGate()
}

@main
@MainActor
struct ProcessGateFixture {
    static func main() throws {
        let args = CommandLine.arguments
        let directory = URL(fileURLWithPath: args[2], isDirectory: true)
        let control = directory.appendingPathComponent("reset-control-v1.json")
        func pending() -> Bool { FileManager.default.fileExists(atPath: control.path) }
        func out(_ text: String) { print(text); fflush(stdout) }
        if args[1] == "writer" {
            let gate = try SharedFileWriterGate(directory: directory, resetPending: pending,
                archive: SharedArchiveNestedLeaseBoundary { work in try SharedArchiveNestedUnit.run(directory: directory, work) })
            let captured = try gate.makeBoundary()
            out("captured")
            while let command = readLine(), command == "write" {
                do {
                    try captured.withEffect { try Data("late personal image".utf8).write(to: directory.appendingPathComponent("late-image.jpg")) }
                    out("WROTE")
                } catch { out("refused") }
            }
        } else {
            let gate = try AccountWriterGate(directory: directory, resetControlExists: pending)
            try gate.acquireResetGate()
            try Data("fixture reset evidence".utf8).write(to: control)
            out("reset-held")
            _ = readLine()
            try gate.validateResetGate()
            try FileManager.default.removeItem(at: control)
            gate.releaseResetGate()
            out("reset-released")
        }
    }
}
