import Foundation

final class RuntimeLogFileWriter: @unchecked Sendable {
    struct Policy: Sendable {
        let maximumFileBytes: Int64
        let maximumTotalBytes: Int64
        let maximumFileCount: Int
        let retentionDays: Int

        static let production = Policy(
            maximumFileBytes: 8 * 1024 * 1024,
            maximumTotalBytes: 50 * 1024 * 1024,
            maximumFileCount: 31,
            retentionDays: 21
        )
    }

    private let directory: URL
    private let policy: Policy
    private let queue = DispatchQueue(label: "cn.jac0bshi.bettergi.mac.runtime-log")
    private let dayFormatter: DateFormatter
    private let lineFormatter: ISO8601DateFormatter
    private var lastPruneAt: Date?

    init(directory: URL, policy: Policy = .production) {
        self.directory = directory
        self.policy = policy
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyyMMdd"
        self.dayFormatter = dayFormatter
        let lineFormatter = ISO8601DateFormatter()
        lineFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.lineFormatter = lineFormatter
    }

    func append(_ entry: LogEntry) {
        queue.async { [self] in
            do {
                try write(entry)
            } catch {
                NSLog("BetterGI runtime log write failed: %@", error.localizedDescription)
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    private func write(_ entry: LogEntry) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let line = format(entry)
        let data = Data(line.utf8)
        let destination = try destinationURL(
            for: entry.timestamp,
            appendingBytes: Int64(data.count),
            fileManager: fileManager
        )
        if !fileManager.fileExists(atPath: destination.path) {
            guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
            }
        }

        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)

        let now = Date()
        if lastPruneAt == nil || now.timeIntervalSince(lastPruneAt!) >= 60 {
            try prune(now: now, fileManager: fileManager)
            lastPruneAt = now
        }
    }

    private func destinationURL(
        for date: Date,
        appendingBytes: Int64,
        fileManager: FileManager
    ) throws -> URL {
        let day = dayFormatter.string(from: date)
        var segment = 0
        while true {
            let suffix = segment == 0 ? "" : "-\(segment)"
            let candidate = directory.appendingPathComponent(
                "better-genshin-impact-\(day)\(suffix).log",
                isDirectory: false
            )
            let currentBytes = try Self.fileSize(candidate, fileManager: fileManager)
            if currentBytes == 0 || currentBytes + appendingBytes <= policy.maximumFileBytes {
                return candidate
            }
            segment += 1
        }
    }

    private func prune(now: Date, fileManager: FileManager) throws {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let cutoff = Calendar.current.date(byAdding: .day, value: -policy.retentionDays, to: now)
            ?? .distantPast
        var files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.lastPathComponent.hasPrefix("better-genshin-impact-")
                && $0.pathExtension == "log"
        }
        .compactMap { url -> (url: URL, modifiedAt: Date, bytes: Int64)? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (
                url,
                values.contentModificationDate ?? .distantPast,
                Int64(values.fileSize ?? 0)
            )
        }

        for file in files where file.modifiedAt < cutoff {
            try fileManager.removeItem(at: file.url)
        }
        files.removeAll { $0.modifiedAt < cutoff }
        files.sort { $0.modifiedAt > $1.modifiedAt }

        var retainedCount = 0
        var retainedBytes: Int64 = 0
        for file in files {
            let exceedsCount = retainedCount >= policy.maximumFileCount
            let exceedsBytes = retainedBytes + file.bytes > policy.maximumTotalBytes
            if exceedsCount || exceedsBytes {
                try fileManager.removeItem(at: file.url)
            } else {
                retainedCount += 1
                retainedBytes += file.bytes
            }
        }
    }

    private func format(_ entry: LogEntry) -> String {
        let messageLimit = 16_000
        let message = entry.message.count <= messageLimit
            ? entry.message
            : String(entry.message.prefix(messageLimit)) + " [truncated]"
        return "[\(lineFormatter.string(from: entry.timestamp))] [\(entry.level.label)] \(message)\n"
    }

    private static func fileSize(_ url: URL, fileManager: FileManager) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

}
