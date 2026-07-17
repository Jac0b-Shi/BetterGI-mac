@testable import MacGI
import Foundation
import Testing

@Suite("BetterGI shell task executor")
struct BGIShellTaskExecutorTests {
    @Test("shell config defaults mirror BetterGI ShellConfig")
    func shellConfigDefaultsMirrorBetterGI() throws {
        let config = BGIShellConfig()
        let data = try JSONEncoder().encode(config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(config.disable == false)
        #expect(config.timeout == 60)
        #expect(config.noWindow == true)
        #expect(config.output == true)
        #expect(object["disable"] as? Bool == false)
        #expect(object["timeout"] as? Int == 60)
        #expect(object["noWindow"] as? Bool == true)
        #expect(object["output"] as? Bool == true)
    }

    @Test("disabled and empty shell commands are skipped without launching")
    func disabledAndEmptyCommandsAreSkipped() async throws {
        let executor = BGIShellTaskExecutor()

        let disabled = try await executor.execute(
            command: "echo should-not-run",
            config: BGIShellConfig(disable: true)
        )
        let empty = try await executor.execute(command: "   ")

        #expect(disabled.status == .disabled)
        #expect(disabled.exitCode == nil)
        #expect(empty.status == .empty)
        #expect(empty.exitCode == nil)
    }

    @Test("shell executor writes command to stdin and captures output")
    func shellExecutorWritesCommandToStdinAndCapturesOutput() async throws {
        let executor = BGIShellTaskExecutor()

        let result = try await executor.execute(
            command: "printf 'hello\\nworld\\n'",
            config: BGIShellConfig(timeout: 2, output: true)
        )

        #expect(result.status == .finished)
        #expect(result.exitCode == 0)
        #expect(result.outputShell == "hello")
        #expect(result.output == "world")
        #expect(result.hasOutput)
    }

    @Test("non-positive timeout launches shell without waiting")
    func nonPositiveTimeoutLaunchesShellWithoutWaiting() async throws {
        let executor = BGIShellTaskExecutor()

        let result = try await executor.execute(
            command: "sleep 0.2",
            config: BGIShellConfig(timeout: 0, output: false)
        )

        #expect(result.status == .launched)
        #expect(result.exitCode == nil)
    }
}
