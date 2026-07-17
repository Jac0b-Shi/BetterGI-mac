import Darwin
import Foundation

struct BGIShellConfig: Equatable, Codable, Sendable {
    var disable: Bool
    var timeout: Int
    var noWindow: Bool
    var output: Bool

    init(
        disable: Bool = false,
        timeout: Int = 60,
        noWindow: Bool = true,
        output: Bool = true
    ) {
        self.disable = disable
        self.timeout = timeout
        self.noWindow = noWindow
        self.output = output
    }
}

struct BGIShellTaskParam: Equatable, Sendable {
    var disable: Bool
    var command: String
    var timeoutSeconds: Int
    var noWindow: Bool
    var output: Bool

    static func buildFromConfig(command: String, config: BGIShellConfig) -> BGIShellTaskParam {
        BGIShellTaskParam(
            disable: config.disable,
            command: command,
            timeoutSeconds: config.timeout,
            noWindow: config.noWindow,
            output: config.output
        )
    }
}

enum BGIShellExecutionStatus: String, Equatable, Sendable {
    case disabled
    case empty
    case launched
    case finished
    case timedOut
    case cancelled
}

struct BGIShellExecutionResult: Equatable, Sendable {
    var command: String
    var status: BGIShellExecutionStatus
    var outputShell: String
    var output: String
    var exitCode: Int32?
    var durationMs: Int

    var hasOutput: Bool {
        !outputShell.isEmpty || !output.isEmpty
    }
}

final class BGIShellTaskExecutor {
    private let shellURL: URL
    private let shellArguments: [String]
    private let pollIntervalNs: UInt64

    init(
        shellURL: URL = URL(fileURLWithPath: "/bin/zsh"),
        shellArguments: [String] = ["-s"],
        pollIntervalNs: UInt64 = 50_000_000
    ) {
        self.shellURL = shellURL
        self.shellArguments = shellArguments
        self.pollIntervalNs = pollIntervalNs
    }

    func execute(command: String, config: BGIShellConfig = BGIShellConfig()) async throws -> BGIShellExecutionResult {
        try await execute(param: .buildFromConfig(command: command, config: config))
    }

    func execute(param: BGIShellTaskParam) async throws -> BGIShellExecutionResult {
        if param.disable {
            return result(command: param.command, status: .disabled)
        }

        let command = param.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.isEmpty {
            return result(command: param.command, status: .empty)
        }

        let startedAt = Date()
        let process = Process()
        process.executableURL = shellURL
        process.arguments = shellArguments

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        let outputPipe = Pipe()
        if param.output {
            process.standardOutput = outputPipe
        }

        try process.run()

        if let data = "\(command)\n".data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        if param.timeoutSeconds <= 0 {
            return result(command: command, status: .launched, startedAt: startedAt)
        }

        let status = await waitForExitOrStop(process: process, timeoutSeconds: param.timeoutSeconds)
        let outputText: String
        if param.output {
            outputText = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else {
            outputText = ""
        }
        let splitOutput = Self.splitOutput(outputText)

        return result(
            command: command,
            status: status,
            outputShell: splitOutput.shell,
            output: splitOutput.output,
            exitCode: process.isRunning ? nil : process.terminationStatus,
            startedAt: startedAt
        )
    }

    private func waitForExitOrStop(process: Process, timeoutSeconds: Int) async -> BGIShellExecutionStatus {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while process.isRunning {
            if Task.isCancelled {
                await stop(process: process)
                return .cancelled
            }
            if Date() >= deadline {
                await stop(process: process)
                return .timedOut
            }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }

        return .finished
    }

    private func stop(process: Process) async {
        process.terminate()
        for _ in 0..<10 {
            if !process.isRunning {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func result(
        command: String,
        status: BGIShellExecutionStatus,
        outputShell: String = "",
        output: String = "",
        exitCode: Int32? = nil,
        startedAt: Date = Date()
    ) -> BGIShellExecutionResult {
        BGIShellExecutionResult(
            command: command,
            status: status,
            outputShell: outputShell,
            output: output,
            exitCode: exitCode,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        )
    }

    private static func splitOutput(_ text: String) -> (shell: String, output: String) {
        let normalized = text.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        guard !normalized.isEmpty else {
            return ("", "")
        }
        let parts = normalized.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let shell = String(parts.first ?? "")
        let output = parts.count > 1 ? String(parts[1]) : ""
        return (shell, output)
    }
}
