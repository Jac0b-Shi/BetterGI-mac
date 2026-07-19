import Foundation
import Security

actor BetterGICoreProcessSupervisor {
    enum State: Equatable, Sendable {
        case stopped
        case running(BetterGICoreHandshake)
        case failed(String)
    }

    private(set) var state: State = .stopped
    private let store: BGIRuntimeResourceStore
    private let executableURL: URL
    private var process: Process?
    private var client: BetterGICoreRPCClient?
    private var callbackClient: BetterGICorePlatformCallbackClient?
    private var callbackTask: Task<Void, Never>?
    private var platformHandler: BetterGICorePlatformCallbackClient.Handler?
    private var processGeneration = 0
    private var controlledRestartCount = 0
    private var intentionalStop = false

    init(store: BGIRuntimeResourceStore = .defaultStore(), executableURL: URL? = nil) throws {
        self.store = store
        self.executableURL = try executableURL ?? Self.resolveExecutableURL()
    }

    func start(platformHandler: @escaping BetterGICorePlatformCallbackClient.Handler) async throws -> BetterGICoreHandshake {
        if case .running(let handshake) = state { return handshake }
        self.platformHandler = platformHandler
        intentionalStop = false
        try store.createDirectorySkeleton()
        let runURL = store.rootURL.appendingPathComponent("Run", isDirectory: true)
        try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
        let socketURL = runURL.appendingPathComponent("core.sock")
        try? FileManager.default.removeItem(at: socketURL)
        let token = Self.makeSessionToken()
        let process = Process()
        processGeneration += 1
        let generation = processGeneration
        process.terminationHandler = { [weak self] _ in
            Task { await self?.processTerminated(generation: generation) }
        }
        process.executableURL = executableURL
        process.arguments = [
            "--runtime-root", store.rootURL.path,
            "--socket", socketURL.path,
            "--session-token", token
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            self.process = process
            let client = BetterGICoreRPCClient(socketPath: socketURL.path, sessionToken: token)
            self.client = client
            try await waitForSocket(socketURL, process: process)
            let callbackClient = BetterGICorePlatformCallbackClient(
                socketPath: socketURL.path,
                sessionToken: token
            )
            self.callbackClient = callbackClient
            callbackTask = Task.detached { [weak self] in
                do {
                    try callbackClient.run(handler: platformHandler)
                } catch {
                    await self?.callbackFailed(error)
                }
            }
            try client.connect()
            let handshake = try client.handshake()
            var callbackAttached = false
            for _ in 0..<40 {
                let initialized = try client.initialize(
                    runtimeRoot: store.rootURL,
                    serverTimeZoneOffsetHours: 8,
                    jsNotificationEnabled: false,
                    mapMatchingMethod: "TemplateMatch"
                )
                if initialized["platformCallbackAttached"] as? Bool == true {
                    guard initialized["scriptHostServicesAttached"] as? Bool == true,
                          initialized["scriptServicePlatformAttached"] as? Bool == true,
                          initialized["platformAssetsInitialized"] as? Bool == true,
                          initialized["mapMatchingMethod"] as? String == "TemplateMatch"
                    else {
                        throw BetterGICoreRPCError.protocolViolation(
                            "Core did not attach the required script services."
                        )
                    }
                    callbackAttached = true
                    break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard callbackAttached else {
                throw BetterGICoreRPCError.socket("Swift platform callback channel did not attach to Core.")
            }
            state = .running(handshake)
            return handshake
        } catch {
            intentionalStop = true
            process.terminate()
            self.process = nil
            client?.disconnect()
            client = nil
            callbackClient?.stop()
            callbackClient = nil
            callbackTask?.cancel()
            callbackTask = nil
            state = .failed(error.localizedDescription)
            intentionalStop = false
            throw error
        }
    }

    func listScriptGroups() throws -> [BetterGIScriptGroupSummary] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.listScriptGroups()
    }

    func getScriptGroup(name: String) throws -> BetterGIScriptGroupDocument {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.getScriptGroup(name: name)
    }

    func saveScriptGroup(name: String, documentData: Data) throws -> BetterGIScriptGroupDocument {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.saveScriptGroup(name: name, documentData: documentData)
    }

    func listScriptProjects() throws -> [BetterGIScriptProjectSummary] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.listScriptProjects()
    }

    func runSchedulerGroup(name: String) throws -> String {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(
            method: "scheduler.run", parameters: ["groupName": name]
        ) as? [String: Any], let taskID = result["taskId"] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid scheduler.run result.")
        }
        return taskID
    }

    func stopScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.stop", parameters: ["taskId": taskID])
    }

    func pauseScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.pause", parameters: ["taskId": taskID])
    }

    func resumeScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.resume", parameters: ["taskId": taskID])
    }

    func stop() {
        intentionalStop = true
        if let client {
            _ = try? client.request(method: "core.shutdown")
            client.disconnect()
        }
        if let process, process.isRunning { process.terminate() }
        callbackClient?.stop()
        callbackTask?.cancel()
        process = nil
        client = nil
        callbackClient = nil
        callbackTask = nil
        state = .stopped
    }

    private func processTerminated(generation: Int) async {
        guard generation == processGeneration, !intentionalStop else { return }
        guard case .running = state else { return }

        client?.disconnect()
        callbackClient?.stop()
        callbackTask?.cancel()
        process = nil
        client = nil
        callbackClient = nil
        callbackTask = nil
        state = .failed("BetterGI Core exited unexpectedly.")

        guard controlledRestartCount == 0, let platformHandler else { return }
        controlledRestartCount = 1
        do {
            _ = try await start(platformHandler: platformHandler)
        } catch {
            state = .failed("BetterGI Core controlled restart failed: \(error.localizedDescription)")
        }
    }

    private func callbackFailed(_ error: Error) {
        guard case .running = state else { return }
        state = .failed("Core platform callback failed: \(error.localizedDescription)")
    }

    private func waitForSocket(_ socketURL: URL, process: Process) async throws {
        for _ in 0..<100 {
            guard process.isRunning else {
                throw BetterGICoreRPCError.socket("BetterGI Core exited before creating its RPC socket.")
            }
            if FileManager.default.fileExists(atPath: socketURL.path) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw BetterGICoreRPCError.socket("Timed out waiting for BetterGI Core RPC socket.")
    }

    private static func resolveExecutableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["BETTERGI_CORE_HOST"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        if let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/BetterGICore/BetterGenshinImpact.Core.Host"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw BetterGICoreRPCError.socket(
            "BetterGI Core Host is not bundled. Set BETTERGI_CORE_HOST for development builds."
        )
    }

    private static func makeSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
