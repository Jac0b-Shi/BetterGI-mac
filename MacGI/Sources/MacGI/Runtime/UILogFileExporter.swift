import Foundation

enum UILogFileExporter {
    private static func makeFileNameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }

    private static func makeLineFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    @discardableResult
    static func export<S: Sequence>(
        entries: S,
        to directory: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL where S.Element == LogEntry {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileNameFormatter = makeFileNameFormatter()
        let lineFormatter = makeLineFormatter()
        let destination = directory.appendingPathComponent(
            "macgi-ui-\(fileNameFormatter.string(from: now)).log",
            isDirectory: false
        )
        let content = entries.map { entry in
            "[\(lineFormatter.string(from: entry.timestamp))] [\(entry.level.label)] \(entry.message)"
        }.joined(separator: "\n") + "\n"
        try content.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }
}
