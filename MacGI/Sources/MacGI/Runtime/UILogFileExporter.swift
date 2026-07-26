import Foundation

enum UILogFileExporter {
    static let defaultMaximumFileCount = 20
    static let defaultMaximumTotalBytes: Int64 = 10 * 1024 * 1024

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
        fileManager: FileManager = .default,
        maximumFileCount: Int = defaultMaximumFileCount,
        maximumTotalBytes: Int64 = defaultMaximumTotalBytes
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
        let encoded = Data(content.utf8)
        let maximumExportBytes = max(0, Int(clamping: maximumTotalBytes))
        let exportData = encoded.count <= maximumExportBytes
            ? encoded
            : Data(encoded.prefix(maximumExportBytes))
        try exportData.write(to: destination, options: .atomic)
        try pruneExports(
            in: directory,
            fileManager: fileManager,
            maximumFileCount: maximumFileCount,
            maximumTotalBytes: maximumTotalBytes
        )
        return destination
    }

    private static func pruneExports(
        in directory: URL,
        fileManager: FileManager,
        maximumFileCount: Int,
        maximumTotalBytes: Int64
    ) throws {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let exports = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("macgi-ui-") && $0.pathExtension == "log" }
        .compactMap { url -> (url: URL, modifiedAt: Date, bytes: Int64)? in
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }

        var retainedCount = 0
        var retainedBytes: Int64 = 0
        for export in exports {
            let exceedsCount = retainedCount >= maximumFileCount
            let exceedsBytes = retainedBytes + export.bytes > maximumTotalBytes
            if exceedsCount || exceedsBytes {
                try fileManager.removeItem(at: export.url)
            } else {
                retainedCount += 1
                retainedBytes += export.bytes
            }
        }
    }
}
