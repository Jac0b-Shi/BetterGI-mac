import Darwin
import Foundation

/// Dedicated authenticated reverse-RPC connection. Core owns business execution and invokes
/// macOS capture/input/window capabilities over this channel; Swift must ACK every operation.
final class BetterGICorePlatformCallbackClient: @unchecked Sendable {
    typealias Handler = @Sendable (_ method: String, _ parameters: [String: Any]?) throws -> Any

    private let socketPath: String
    private let sessionToken: String
    private let stateLock = NSLock()
    private var descriptor: Int32 = -1
    private var stopped = false

    init(socketPath: String, sessionToken: String) {
        self.socketPath = socketPath
        self.sessionToken = sessionToken
    }

    deinit { stop() }

    func run(handler: Handler) throws {
        let fd = try connectSocket()
        stateLock.withLock {
            guard !stopped else { return }
            descriptor = fd
        }
        defer {
            stateLock.withLock {
                if descriptor == fd { descriptor = -1 }
            }
            Darwin.close(fd)
        }

        let attachID = UUID().uuidString
        try writeEnvelope([
            "id": attachID,
            "method": "platform.attach",
            "sessionToken": sessionToken,
        ], descriptor: fd)
        let attach = try readEnvelope(descriptor: fd)
        guard attach["id"] as? String == attachID,
              attach["error"] == nil,
              (attach["result"] as? [String: Any])?["attached"] as? Bool == true
        else { throw BetterGICoreRPCError.protocolViolation("Core rejected platform.attach.") }

        while !stateLock.withLock({ stopped }) {
            let request = try readEnvelope(descriptor: fd)
            guard let id = request["id"] as? String,
                  let method = request["method"] as? String,
                  request["sessionToken"] as? String == sessionToken
            else {
                throw BetterGICoreRPCError.protocolViolation("Invalid Core platform callback request.")
            }
            do {
                let result = try handler(method, request["params"] as? [String: Any])
                try writeEnvelope(["id": id, "result": result], descriptor: fd)
            } catch {
                try writeEnvelope([
                    "id": id,
                    "error": [
                        "code": "PlatformCallbackFailed",
                        "message": error.localizedDescription,
                    ],
                ], descriptor: fd)
            }
        }
    }

    func stop() {
        let fd = stateLock.withLock { () -> Int32 in
            stopped = true
            let current = descriptor
            descriptor = -1
            return current
        }
        if fd >= 0 { Darwin.shutdown(fd, SHUT_RDWR) }
    }

    private func connectSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        do {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8CString)
            guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
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
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private func writeEnvelope(_ envelope: [String: Any], descriptor: Int32) throws {
        let body = try JSONSerialization.data(withJSONObject: envelope)
        guard body.count <= BetterGICoreRPCClient.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("Platform callback frame is too large.")
        }
        var length = UInt32(body.count).littleEndian
        try withUnsafeBytes(of: &length) { try writeAll($0, descriptor: descriptor) }
        try body.withUnsafeBytes { try writeAll($0, descriptor: descriptor) }
    }

    private func readEnvelope(descriptor: Int32) throws -> [String: Any] {
        let header = try readExactly(count: 4, descriptor: descriptor)
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard length > 0, length <= BetterGICoreRPCClient.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("Invalid platform callback frame length \(length).")
        }
        let body = try readExactly(count: Int(length), descriptor: descriptor)
        guard let envelope = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Platform callback payload is not a JSON object.")
        }
        return envelope
    }

    private func writeAll(_ bytes: UnsafeRawBufferPointer, descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            guard count > 0 else { throw posixError("write") }
            offset += count
        }
    }

    private func readExactly(count: Int, descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset)
                guard received > 0 else {
                    throw BetterGICoreRPCError.socket("Core platform callback channel disconnected.")
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
