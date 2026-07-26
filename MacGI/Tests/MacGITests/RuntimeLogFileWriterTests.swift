import Foundation
@testable import MacGI
import Testing

@Suite("Runtime log file writer")
struct RuntimeLogFileWriterTests {
    @Test("automatically appends HUD logs and keeps storage bounded")
    func appendsAndPrunes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let oldLog = root.appendingPathComponent("better-genshin-impact-20200101.log")
        try "old\n".write(to: oldLog, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: oldLog.path
        )

        let writer = RuntimeLogFileWriter(
            directory: root,
            policy: .init(
                maximumFileBytes: 1_024,
                maximumTotalBytes: 2_048,
                maximumFileCount: 2,
                retentionDays: 21
            )
        )
        writer.append(LogEntry(timestamp: Date(), level: .info, message: "Core ready"))
        writer.append(LogEntry(timestamp: Date(), level: .error, message: "Input ACK failed"))
        writer.flush()

        let logs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("better-genshin-impact-") }
        #expect(logs.count == 1)
        #expect(!FileManager.default.fileExists(atPath: oldLog.path))
        let content = try String(contentsOf: logs[0], encoding: .utf8)
        #expect(content.contains("[INF] Core ready"))
        #expect(content.contains("[ERR] Input ACK failed"))
    }
}
