import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol CommandExecuting: Sendable {
    func run(_ executable: String, arguments: [String], currentDirectory: String?) throws -> CommandResult
}

private final class DataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func set(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data = newData
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public struct ProcessCommandExecutor: CommandExecuting {
    public init() {}

    public func run(_ executable: String, arguments: [String], currentDirectory: String?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = DataBuffer()
        let stderrBuffer = DataBuffer()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutBuffer.set(data)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrBuffer.set(data)
            group.leave()
        }

        try process.run()
        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutBuffer.get(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.get(), encoding: .utf8) ?? ""
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

public func findBdPath(executor: CommandExecuting = ProcessCommandExecutor()) -> String {
    let candidates = [
        "/opt/homebrew/bin/bd",
        "/usr/local/bin/bd"
    ]
    for candidate in candidates {
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
    }
    if let result = try? executor.run("/usr/bin/which", arguments: ["bd"], currentDirectory: nil), result.exitCode == 0 {
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { return path }
    }
    return "bd"
}
