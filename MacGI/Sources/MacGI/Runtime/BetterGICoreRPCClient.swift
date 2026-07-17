import Darwin
import Foundation

enum BetterGICoreRPCError: Error, LocalizedError, Equatable {
    case socket(String)
    case protocolViolation(String)
    case remote(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .socket(let message): message
        case .protocolViolation(let message): message
        case .remote(let code, let message): "Core RPC \(code): \(message)"
        }
    }
}

struct BetterGICoreHandshake: Equatable, Sendable {
    let protocolVersion: Int
    let runtimeVersion: String
    let architecture: String
    let openCVVersion: String
    let clearScriptReady: Bool
    let capabilities: [String]
}

struct BetterGIScriptGroupSummary: Equatable, Sendable {
    let name: String
    let path: String
}

struct BetterGIScriptGroupDocument: Sendable {
    let name: String
    let path: String
    let documentData: Data
}

struct BetterGIScriptProjectSummary: Equatable, Sendable {
    let folderName: String
    let manifestJSON: String
}

/// Blocking request/response transport. Call it from a worker task, never the main actor.
final class BetterGICoreRPCClient: @unchecked Sendable {
    static let protocolVersion = 1
    static let maximumFrameLength = 16 * 1024 * 1024

    private let socketPath: String
    private let sessionToken: String
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    init(socketPath: String, sessionToken: String) {
        self.socketPath = socketPath
        self.sessionToken = sessionToken
    }

    deinit { disconnect() }

    func connect() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor < 0 else { return }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        do {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8CString)
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= pathCapacity else {
                throw BetterGICoreRPCError.socket("Core socket path exceeds sockaddr_un capacity.")
            }
            _ = withUnsafeMutablePointer(to: &address.sun_path) { target in
                pathBytes.withUnsafeBytes { source in
                    memcpy(target, source.baseAddress!, pathBytes.count)
                }
            }
            let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, length)
                }
            }
            guard result == 0 else { throw posixError("connect") }
            descriptor = fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    func handshake() throws -> BetterGICoreHandshake {
        guard let result = try request(method: "core.handshake") as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid core.handshake result.")
        }
        guard
            let version = result["protocolVersion"] as? Int,
            let runtime = result["runtimeVersion"] as? String,
            let architecture = result["architecture"] as? String,
            let openCV = result["openCvVersion"] as? String,
            let clearScript = result["clearScriptReady"] as? Bool,
            let capabilities = result["capabilities"] as? [String]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid core.handshake result.") }
        guard version == Self.protocolVersion else {
            throw BetterGICoreRPCError.protocolViolation(
                "Protocol mismatch: Swift=\(Self.protocolVersion), Core=\(version)."
            )
        }
        return BetterGICoreHandshake(
            protocolVersion: version,
            runtimeVersion: runtime,
            architecture: architecture,
            openCVVersion: openCV,
            clearScriptReady: clearScript,
            capabilities: capabilities
        )
    }

    func initialize(
        runtimeRoot: URL,
        serverTimeZoneOffsetHours: Double,
        jsNotificationEnabled: Bool,
        mapMatchingMethod: String
    ) throws -> [String: Any] {
        guard let result = try request(
            method: "core.initialize",
            parameters: [
                "runtimeRoot": runtimeRoot.path,
                "serverTimeZoneOffsetHours": serverTimeZoneOffsetHours,
                "jsNotificationEnabled": jsNotificationEnabled,
                "mapMatchingMethod": mapMatchingMethod,
            ]
        ) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid core.initialize result.")
        }
        return result
    }

    func listScriptGroups() throws -> [BetterGIScriptGroupSummary] {
        guard let items = try request(method: "catalog.listScriptGroups") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script-group catalog result.")
        }
        return try items.map { item in
            guard let name = item["name"] as? String, let path = item["path"] as? String else {
                throw BetterGICoreRPCError.protocolViolation("Invalid script-group summary.")
            }
            return BetterGIScriptGroupSummary(name: name, path: path)
        }
    }

    func getScriptGroup(name: String) throws -> BetterGIScriptGroupDocument {
        guard let item = try request(
            method: "catalog.getScriptGroup",
            parameters: ["name": name]
        ) as? [String: Any],
        let responseName = item["name"] as? String,
        let path = item["path"] as? String,
        let document = item["document"] as? [String: Any],
        JSONSerialization.isValidJSONObject(document)
        else { throw BetterGICoreRPCError.protocolViolation("Invalid script-group document.") }
        return BetterGIScriptGroupDocument(
            name: responseName,
            path: path,
            documentData: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        )
    }

    func listScriptProjects() throws -> [BetterGIScriptProjectSummary] {
        guard let items = try request(method: "catalog.listScriptProjects") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script-project catalog result.")
        }
        return try items.map { item in
            guard let folderName = item["folderName"] as? String,
                  let manifest = item["manifest"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(manifest)
            else { throw BetterGICoreRPCError.protocolViolation("Invalid script-project summary.") }
            return BetterGIScriptProjectSummary(
                folderName: folderName,
                manifestJSON: String(
                    data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
                    encoding: .utf8
                ) ?? "{}"
            )
        }
    }

    @discardableResult
    func request(method: String, parameters: [String: Any]? = nil) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { throw BetterGICoreRPCError.socket("Core RPC is not connected.") }
        let id = UUID().uuidString
        var envelope: [String: Any] = [
            "id": id,
            "method": method,
            "sessionToken": sessionToken
        ]
        if let parameters { envelope["params"] = parameters }
        let body = try JSONSerialization.data(withJSONObject: envelope)
        guard body.count <= Self.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("RPC request frame is too large.")
        }
        var length = UInt32(body.count).littleEndian
        try withUnsafeBytes(of: &length) { try writeAll($0) }
        try body.withUnsafeBytes { try writeAll($0) }

        let header = try readExactly(count: 4)
        let responseLength = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard responseLength > 0, responseLength <= Self.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("Invalid RPC response frame length \(responseLength).")
        }
        let responseData = try readExactly(count: Int(responseLength))
        guard
            let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            response["id"] as? String == id
        else { throw BetterGICoreRPCError.protocolViolation("RPC response id does not match request.") }
        if let error = response["error"] as? [String: Any] {
            throw BetterGICoreRPCError.remote(
                code: error["code"] as? String ?? "Unknown",
                message: error["message"] as? String ?? "Core returned an error without a message."
            )
        }
        guard let result = response["result"] else {
            throw BetterGICoreRPCError.protocolViolation("RPC response has neither result nor error.")
        }
        return result
    }

    private func writeAll(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            guard count > 0 else { throw posixError("write") }
            offset += count
        }
    }

    private func readExactly(count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset)
                guard received > 0 else {
                    throw BetterGICoreRPCError.socket("Core RPC disconnected while reading a frame.")
                }
                offset += received
            }
        }
        return data
    }

    private func posixError(_ operation: String) -> BetterGICoreRPCError {
        BetterGICoreRPCError.socket("\(operation) failed: \(String(cString: strerror(errno)))")
    }
}
