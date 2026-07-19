import Foundation
@testable import MacGI
import Testing

@Suite("UI log file exporter")
struct UILogFileExporterTests {
    @Test("exports chronological UTF-8 log lines to the runtime log directory")
    func exportsRealLogFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let entries = [
            LogEntry(timestamp: Date(timeIntervalSince1970: 1), level: .info, message: "Core ready"),
            LogEntry(timestamp: Date(timeIntervalSince1970: 2), level: .error, message: "Input ACK failed")
        ]
        let destination = try UILogFileExporter.export(
            entries: entries,
            to: root,
            now: Date(timeIntervalSince1970: 3)
        )
        let content = try String(contentsOf: destination, encoding: .utf8)

        #expect(destination.deletingLastPathComponent() == root)
        #expect(destination.lastPathComponent.hasPrefix("macgi-ui-"))
        #expect(content.contains("[INF] Core ready"))
        #expect(content.contains("[ERR] Input ACK failed"))
        #expect(content.range(of: "Core ready")!.lowerBound < content.range(of: "Input ACK failed")!.lowerBound)
        #expect(content.hasSuffix("\n"))
    }
}
