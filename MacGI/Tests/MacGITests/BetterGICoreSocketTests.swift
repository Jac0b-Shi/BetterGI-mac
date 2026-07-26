import Darwin
import Testing
@testable import MacGI

@Suite("BetterGI Core socket transport")
struct BetterGICoreSocketTests {
    @Test("Suppresses SIGPIPE on disconnected Core sockets")
    func suppressesSIGPIPE() throws {
        let descriptor = try BetterGICoreSocket.makeStreamSocket()
        defer { Darwin.close(descriptor) }

        var value: Int32 = 0
        var valueLength = socklen_t(MemoryLayout.size(ofValue: value))
        let result = Darwin.getsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &value,
            &valueLength)

        #expect(result == 0)
        #expect(value == 1)
    }
}
