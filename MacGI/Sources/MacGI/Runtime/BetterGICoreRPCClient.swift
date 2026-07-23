import Darwin
import CoreFoundation
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

struct BetterGIScriptGroupProjectSummary: Equatable, Sendable, Identifiable {
    let index: Int
    let name: String
    let type: String
    let status: String
    let schedule: String
    let runNum: Int
    let folderName: String
    let hasCustomSettings: Bool
    let nextFlag: Bool

    var id: String { "\(index)|\(type)|\(name)" }
}

enum BetterGIJSONValue: Equatable, Sendable {
    case null
    case string(String)
    case bool(Bool)
    case strings([String])
    case integer(Int64)
    case number(Double)
    case array([BetterGIJSONValue])
    case object([String: BetterGIJSONValue])

    init(any: Any) throws {
        switch any {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as [String]:
            self = .strings(value)
        case let value as [Any]:
            self = .array(try value.map(Self.init(any:)))
        case let value as [String: Any]:
            self = .object(try value.mapValues(Self.init(any:)))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .number(value.doubleValue)
            } else {
                self = .integer(value.int64Value)
            }
        default:
            throw BetterGICoreRPCError.protocolViolation(
                "Unsupported JSON settings value: \(String(describing: type(of: any)))."
            )
        }
    }

    var any: Any {
        switch self {
        case .null: NSNull()
        case .string(let value): value
        case .bool(let value): value
        case .strings(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .array(let value): value.map(\.any)
        case .object(let value): value.mapValues(\.any)
        }
    }
}

struct BetterGISettingItem: Equatable, Sendable, Identifiable {
    let name: String
    let type: String
    let label: String
    let options: [String]
    let cascadeOptions: [String: [String]]
    let defaultValue: BetterGIJSONValue?
    var id: String { "\(type)|\(name)|\(label)" }
}

struct BetterGIProjectCustomSettings: Equatable, Sendable {
    let projectIndex: Int
    let schema: [BetterGISettingItem]
    var values: [String: BetterGIJSONValue]
}

struct BetterGIProjectCommonSettings: Equatable, Sendable {
    let projectIndex: Int
    var status: String
    let isJavascript: Bool
    var allowJsNotification: Bool
    var allowJsHTTP: Bool
    let httpAllowedURLs: [String]
}

struct BetterGIAddCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let folderName: String
    let type: String
}

enum BetterGISchedulerCatalogMutation: Sendable {
    case add(type: String, candidateIDs: [String], shellCommand: String?)
    case remove(projectIndex: Int, sameFolder: Bool)
    case clear
    case reverse
    case updatePathingFolders
    case setNext(projectIndex: Int)
}

struct BetterGIGroupConfigSettings: Equatable, Sendable {
    var enabled: Bool; var autoPick: Bool; var autoEat: Bool; var autoSkip: Bool; var autoFight: Bool; var autoRun: Bool
    var partyName: String; var visitStatue: Bool; var mainAvatar: String; var guardianAvatar: String; var guardianInterval: String
    var guardianLongPress: Bool; var gadgetInterval: Int; var skipDuring: String; var hideOnRepeat: Bool
    var enableShellConfig: Bool; var shellDisable: Bool; var shellTimeout: Int; var shellNoWindow: Bool; var shellOutput: Bool
}

struct BetterGIScriptGroupSummary: Equatable, Sendable, Identifiable {
    let name: String
    let path: String
    let index: Int
    let projects: [BetterGIScriptGroupProjectSummary]

    var id: String { "\(index)|\(name)" }
}

struct BetterGIScriptProjectSummary: Equatable, Sendable, Identifiable {
    let folderName: String
    let name: String
    let version: String

    var id: String { folderName }
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
            guard let name = item["name"] as? String,
                  let path = item["path"] as? String,
                  let index = item["index"] as? Int,
                  let projectItems = item["projects"] as? [[String: Any]]
            else {
                throw BetterGICoreRPCError.protocolViolation("Invalid script-group summary.")
            }
            let projects = try projectItems.map { project -> BetterGIScriptGroupProjectSummary in
                guard let projectIndex = project["index"] as? Int,
                      let projectName = project["name"] as? String,
                      let type = project["type"] as? String,
                      let status = project["status"] as? String,
                      let schedule = project["schedule"] as? String,
                      let runNum = project["runNum"] as? Int,
                      let folderName = project["folderName"] as? String,
                      let hasCustomSettings = project["hasCustomSettings"] as? Bool,
                      let nextFlag = project["nextFlag"] as? Bool
                else { throw BetterGICoreRPCError.protocolViolation("Invalid script-group project summary.") }
                return BetterGIScriptGroupProjectSummary(
                    index: projectIndex,
                    name: projectName,
                    type: type,
                    status: status,
                    schedule: schedule,
                    runNum: runNum,
                    folderName: folderName,
                    hasCustomSettings: hasCustomSettings,
                    nextFlag: nextFlag
                )
            }
            return BetterGIScriptGroupSummary(name: name, path: path, index: index, projects: projects)
        }
    }

    func projectCommonSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCommonSettings {
        guard let item = try request(method: "catalog.getScriptGroupProjectCommonSettings", parameters: [
            "name": groupName, "projectIndex": projectIndex
        ]) as? [String: Any],
              let index = item["index"] as? Int,
              let status = item["status"] as? String,
              let isJavascript = item["isJavascript"] as? Bool,
              let allowHTTP = item["allowJsHttp"] as? Bool,
              let urls = item["httpAllowedUrls"] as? [String]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid project common settings.") }
        return BetterGIProjectCommonSettings(
            projectIndex: index, status: status, isJavascript: isJavascript,
            allowJsNotification: item["allowJsNotification"] as? Bool ?? true,
            allowJsHTTP: allowHTTP, httpAllowedURLs: urls)
    }

    func projectCustomSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCustomSettings {
        guard let item = try request(method: "catalog.getScriptGroupProjectCustomSettings", parameters: [
            "name": groupName, "projectIndex": projectIndex
        ]) as? [String: Any], let index = item["index"] as? Int,
              let schemaItems = item["schema"] as? [[String: Any]],
              let rawValues = item["values"] as? [String: Any]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid project custom settings.") }
        let schema = try schemaItems.map { raw -> BetterGISettingItem in
            guard let name = raw["name"] as? String, let type = raw["type"] as? String,
                  let label = raw["label"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid custom setting schema.") }
            let defaultValue = try raw["default"].map(BetterGIJSONValue.init(any:))
            return BetterGISettingItem(name: name, type: type, label: label,
                options: raw["options"] as? [String] ?? [],
                cascadeOptions: raw["cascadeOptions"] as? [String: [String]] ?? [:],
                defaultValue: defaultValue)
        }
        let values = try rawValues.mapValues(BetterGIJSONValue.init(any:))
        return BetterGIProjectCustomSettings(projectIndex: index, schema: schema, values: values)
    }

    func listAddCandidates(type: String) throws -> [BetterGIAddCandidate] {
        guard let items = try request(method: "catalog.listScriptGroupAddCandidates", parameters: ["type": type]) as? [[String: Any]]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid add-candidate catalog.") }
        return try items.map { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let folder = item["folderName"] as? String, let type = item["type"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid add candidate.") }
            return BetterGIAddCandidate(id: id, name: name, folderName: folder, type: type)
        }
    }

    func listScriptProjects() throws -> [BetterGIScriptProjectSummary] {
        guard let items = try request(method: "catalog.listScriptProjects") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script-project catalog result.")
        }
        return try items.map { item in
            guard let folderName = item["folderName"] as? String,
                  let name = item["name"] as? String,
                  let version = item["version"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid script-project summary.") }
            return BetterGIScriptProjectSummary(folderName: folderName, name: name, version: version)
        }
    }

    func scriptProjectRootLocation() throws -> String {
        guard let result = try request(method: "catalog.getScriptProjectRootLocation") as? [String: Any],
              let path = result["path"] as? String
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script project root location.")
        }
        return path
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
