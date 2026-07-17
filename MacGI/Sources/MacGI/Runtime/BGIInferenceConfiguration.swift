import Foundation

// MARK: - Compute preference

/// Hardware compute preference for ONNX Runtime inference.
///
/// Core ML EP does not provide a strict "ANE → GPU → CPU" fallback chain.
/// It *allows* Core ML to schedule compatible ops on the requested hardware;
/// unsupported ops stay on ORT CPU EP.  Whether a particular model actually
/// runs on ANE depends on model compatibility, Core ML scheduling, and the
/// current device state.
///
/// - `automatic`: Core ML EP with all compute units if available; CPU EP
///   for unsupported ops.  Apple Silicon with ANE benefits most.
/// - `coreMLAll`: Core ML EP, compute units = All (CPU + GPU + Neural Engine).
///   Same effective behaviour as `automatic` on Apple Silicon.
/// - `coreMLCPUAndGPU`: Core ML EP, compute units = CPU + GPU only.
///   Useful when ANE is unavailable or being profiled in isolation.
/// - `cpuOnly`: ORT CPU EP only; no hardware acceleration registered.
enum BGIComputePreference: String, CaseIterable, Sendable {
    case automatic
    case coreMLAll
    case coreMLCPUAndGPU
    case cpuOnly
}

// MARK: - Per-model execution policy

/// Model-level overrides that let specific models opt out of Core ML EP
/// or tune options independently of the global preference.
struct BGIModelExecutionPolicy: Equatable, Sendable {
    /// Set `true` to skip Core ML EP for this model entirely.
    let coreMLDisabled: Bool
    /// Preferred Core ML model format (`MLProgram` or `NeuralNetwork`).
    /// `nil` means use the factory default.
    let coreMLModelFormat: String?
    /// Override compute units for this model; `nil` inherits from global
    /// preference.
    let coreMLComputeUnits: String?
    /// Override `RequireStaticInputShapes`; `nil` inherits from factory default.
    let requireStaticInputShapes: Bool?

    static let `default` = BGIModelExecutionPolicy(
        coreMLDisabled: false,
        coreMLModelFormat: nil,
        coreMLComputeUnits: nil,
        requireStaticInputShapes: nil
    )

    static let coreMLDisabledPolicy = BGIModelExecutionPolicy(
        coreMLDisabled: true,
        coreMLModelFormat: nil,
        coreMLComputeUnits: nil,
        requireStaticInputShapes: nil
    )
}

// MARK: - Resolved Core ML options

/// The concrete Core ML EP options derived from the global preference and
/// per-model policy.  Used consistently for session options, cache keys, and
/// Debug UI so they never drift apart.
struct BGIResolvedCoreMLOptions: Equatable, Sendable {
    let modelFormat: String
    let computeUnits: String
    let requireStaticInputShapes: String
    let enableOnSubgraphs: String

    static let factoryDefaults = BGIResolvedCoreMLOptions(
        modelFormat: "MLProgram",
        computeUnits: "All",
        requireStaticInputShapes: "0",
        enableOnSubgraphs: "0"
    )

    /// Stable cache token that includes every option affecting model
    /// compilation.  When any option changes the token changes, so stale
    /// caches are never silently reused.
    var cacheToken: String {
        [
            "format=\(modelFormat)",
            "compute=\(computeUnits)",
            "static=\(requireStaticInputShapes)",
            "subgraphs=\(enableOnSubgraphs)"
        ].joined(separator: "|")
    }
}

// MARK: - Inference backend result (replaces ambiguous booleans)

/// The actual backend that was used to create the final session.
enum BGIInferenceBackendResult: Equatable, Sendable {
    /// Core ML EP was appended and the session was created successfully.
    case coreML(BGIResolvedCoreMLOptions)
    /// CPU-only session (either requested or fallback).
    case cpuOnly
    /// Core ML was attempted but compilation failed; rebuilt with CPU EP.
    case cpuFallbackFromCoreML
    /// Session creation failed entirely.
    case failed

    var displayName: String {
        switch self {
        case .coreML(let opts):   return "Core ML (\(opts.modelFormat)/\(opts.computeUnits))"
        case .cpuOnly:            return "CPU only"
        case .cpuFallbackFromCoreML: return "Core ML → CPU"
        case .failed:             return "Failed"
        }
    }
}

// MARK: - EP assignment snapshot

/// Captured after session creation so Debug UI can show what actually happened.
struct BGIEpAssignment: Equatable, Sendable {
    /// The user's requested compute preference.
    let requestedPreference: BGIComputePreference
    /// The actual backend used for the final session.
    let finalBackend: BGIInferenceBackendResult
    /// Whether Core ML EP was attempted (accounts for policy + denylist).
    let coreMLAttempted: Bool
    /// Whether the session creation itself succeeded.
    let sessionCreated: Bool
    /// Reserved for future ORT profiling integration; currently -1.
    let coreMLAssignedNodes: Int
    /// Reserved for future ORT profiling integration; currently -1.
    let totalNodes: Int
    /// Session initialisation wall-clock (ms).
    let sessionInitMs: Double
    /// Any human-readable diagnostics collected during creation.
    let diagnostics: [String]

    static let unknown = BGIEpAssignment(
        requestedPreference: .cpuOnly,
        finalBackend: .failed,
        coreMLAttempted: false,
        sessionCreated: false,
        coreMLAssignedNodes: -1,
        totalNodes: -1,
        sessionInitMs: 0,
        diagnostics: []
    )

    var summary: String {
        var parts: [String] = []
        if sessionCreated {
            parts.append(finalBackend.displayName)
        } else {
            parts.append("Session creation failed")
        }
        if !diagnostics.isEmpty {
            parts.append(diagnostics.joined(separator: "; "))
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Session factory

#if canImport(OnnxRuntimeBindings)
import CommonCrypto
import OnnxRuntimeBindings

// MARK: - Version constants (keep in sync with Package.resolved)

enum BGIRuntimeVersion {
    /// ONNX Runtime version baked into the SPM package.
    /// Must be updated whenever `Package.resolved` bumps the ORT revision.
    static let onnxRuntime = "1.24.2"
}

enum BGIInferenceSessionFactory {
    /// Returns `true` when the ORT build includes Core ML EP and the runtime can
    /// register it.  This does **not** guarantee any model will actually be
    /// scheduled on Core ML, let alone on ANE.
    static var isCoreMLAvailable: Bool {
        ORTIsCoreMLExecutionProviderAvailable()
    }

    // MARK: - Model-level denylist

    /// Models that are known to perform worse, produce diverging results, or fail
    /// to compile under Core ML EP.  Add entries when profiling reveals issues.
    static let coreMLDisabledModels: Set<String> = [
        // "SileroVad",   // example: tiny stateful model, EP overhead > gain
    ]

    static func isCoreMLDisabled(for model: BGIOnnxModel) -> Bool {
        coreMLDisabledModels.contains(model.name)
    }

    // MARK: - Unified Core ML eligibility check

    /// The single source of truth for "should we even attempt Core ML EP?"
    /// Used by both `makeSessionOptions` and `makeResilientSession` so the
    /// assignment snapshot never disagrees with the actual session options.
    static func shouldRegisterCoreML(
        preference: BGIComputePreference,
        policy: BGIModelExecutionPolicy,
        model: BGIOnnxModel?
    ) -> Bool {
        preference != .cpuOnly
            && isCoreMLAvailable
            && !policy.coreMLDisabled
            && (model.map { !isCoreMLDisabled(for: $0) } ?? true)
    }

    // MARK: - Resolved Core ML options

    /// Derive the concrete Core ML EP options from preference + policy.
    /// The same resolved options feed session creation, cache keys, and Debug UI.
    static func resolveCoreMLOptions(
        preference: BGIComputePreference,
        policy: BGIModelExecutionPolicy
    ) -> BGIResolvedCoreMLOptions {
        let defaults = BGIResolvedCoreMLOptions.factoryDefaults

        let modelFormat = policy.coreMLModelFormat ?? defaults.modelFormat

        let computeUnits: String
        if let override = policy.coreMLComputeUnits {
            computeUnits = override
        } else {
            switch preference {
            case .automatic, .coreMLAll: computeUnits = "All"
            case .coreMLCPUAndGPU:       computeUnits = "CPUAndGPU"
            case .cpuOnly:               computeUnits = "CPUOnly"
            }
        }

        let staticShapes: String
        if let override = policy.requireStaticInputShapes {
            staticShapes = override ? "1" : "0"
        } else {
            staticShapes = defaults.requireStaticInputShapes
        }

        return BGIResolvedCoreMLOptions(
            modelFormat: modelFormat,
            computeUnits: computeUnits,
            requireStaticInputShapes: staticShapes,
            enableOnSubgraphs: defaults.enableOnSubgraphs
        )
    }

    // MARK: - Session options

    /// Build `ORTSessionOptions` for the given preference and model policy.
    ///
    /// Core ML EP is registered when `shouldRegisterCoreML(preference:policy:model:)`
    /// returns `true`.
    static func makeSessionOptions(
        preference: BGIComputePreference,
        policy: BGIModelExecutionPolicy = .default,
        model: BGIOnnxModel? = nil,
        modelCacheKey: String? = nil,
        logSeverity: ORTLoggingLevel = .warning
    ) throws -> ORTSessionOptions {
        let options = try ORTSessionOptions()
        try options.setLogSeverityLevel(logSeverity)

        let coreMLRequested = shouldRegisterCoreML(
            preference: preference,
            policy: policy,
            model: model
        )
        guard coreMLRequested else {
            return options
        }

        let resolved = resolveCoreMLOptions(preference: preference, policy: policy)
        var coreMLOptions: [String: String] = [
            "ModelFormat": resolved.modelFormat,
            "MLComputeUnits": resolved.computeUnits,
            "RequireStaticInputShapes": resolved.requireStaticInputShapes,
            "EnableOnSubgraphs": resolved.enableOnSubgraphs
        ]

        if let key = modelCacheKey {
            coreMLOptions["ModelCacheDirectory"] = key
        }

        try options.appendCoreMLExecutionProvider(withOptionsV2: coreMLOptions)
        return options
    }

    // MARK: - Resilient session creation with fallback

    /// Try to create an `ORTSession` with the requested preference + policy.
    ///
    /// If the first attempt fails (e.g. Core ML compilation error, unsupported
    /// op, dynamic shape incompatibility), the factory automatically retries
    /// with `.cpuOnly`.
    ///
    /// Returns the session together with an `BGIEpAssignment` that describes
    /// what actually got registered.
    static func makeResilientSession(
        env: ORTEnv,
        modelPath: String,
        preference: BGIComputePreference = .automatic,
        policy: BGIModelExecutionPolicy = .default,
        model: BGIOnnxModel? = nil,
        modelCacheKey: String? = nil,
        logSeverity: ORTLoggingLevel = .warning
    ) throws -> (session: ORTSession, assignment: BGIEpAssignment) {
        var diagnostics: [String] = []
        let startedAt = Date()
        let coreMLRequested = shouldRegisterCoreML(
            preference: preference,
            policy: policy,
            model: model
        )
        let resolved = coreMLRequested
            ? resolveCoreMLOptions(preference: preference, policy: policy)
            : nil

        // Attempt 1 — requested preference
        let attemptLabel = coreMLRequested ? "Core ML session" : "CPU session"
        do {
            let opts = try makeSessionOptions(
                preference: preference,
                policy: policy,
                model: model,
                modelCacheKey: modelCacheKey,
                logSeverity: logSeverity
            )
            let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
            let initMs = Date().timeIntervalSince(startedAt) * 1000

            let backend: BGIInferenceBackendResult = {
                if coreMLRequested, let r = resolved { return .coreML(r) }
                return .cpuOnly
            }()

            return (
                session: session,
                assignment: BGIEpAssignment(
                    requestedPreference: preference,
                    finalBackend: backend,
                    coreMLAttempted: coreMLRequested,
                    sessionCreated: true,
                    coreMLAssignedNodes: -1,
                    totalNodes: -1,
                    sessionInitMs: initMs,
                    diagnostics: diagnostics
                )
            )
        } catch {
            diagnostics.append("\(attemptLabel) creation failed: \(error.localizedDescription)")
        }

        // Attempt 2 — CPU fallback (only when Core ML was requested)
        guard coreMLRequested else {
            throw BGIInferenceSessionError.allAttemptsFailed(diagnostics)
        }

        diagnostics.append("Falling back to CPU EP")
        do {
            let cpuOpts = try makeSessionOptions(
                preference: .cpuOnly,
                policy: policy,
                model: model,
                logSeverity: logSeverity
            )
            let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: cpuOpts)
            let initMs = Date().timeIntervalSince(startedAt) * 1000

            return (
                session: session,
                assignment: BGIEpAssignment(
                    requestedPreference: preference,
                    finalBackend: .cpuFallbackFromCoreML,
                    coreMLAttempted: true,
                    sessionCreated: true,
                    coreMLAssignedNodes: 0,
                    totalNodes: -1,
                    sessionInitMs: initMs,
                    diagnostics: diagnostics
                )
            )
        } catch {
            diagnostics.append("CPU fallback also failed: \(error.localizedDescription)")
            throw BGIInferenceSessionError.allAttemptsFailed(diagnostics)
        }
    }

    // MARK: - Cache directory management

    /// Derive a content-addressed cache directory so stale caches are never
    /// reused after model updates, ORT version bumps, or option changes.
    ///
    /// Structure: `Cache/CoreML/<onnx-sha256>/<ort-version>/<options-hash>/`
    ///
    /// Returns `nil` when the model file cannot be hashed.
    static func coreMLCacheDirectory(
        forModelAt modelURL: URL,
        ortVersion: String = BGIRuntimeVersion.onnxRuntime,
        resolvedOptions: BGIResolvedCoreMLOptions
    ) -> URL? {
        guard let modelHash = sha256OfFile(at: modelURL) else { return nil }
        let optionsToken = "ort=\(ortVersion)|\(resolvedOptions.cacheToken)"
        let optionsHash = sha256OfString(optionsToken)

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return cachesDir
            .appendingPathComponent("betterGI-mac/CoreML/\(modelHash)/\(optionsHash)")
    }

    /// Prepare and return the cache directory, creating it on disk if needed.
    /// Returns `nil` when the model hash fails, the directory cannot be created,
    /// or the path exists as a regular file (not a directory).
    static func prepareCoreMLCacheDirectory(
        forModelAt modelURL: URL,
        ortVersion: String = BGIRuntimeVersion.onnxRuntime,
        resolvedOptions: BGIResolvedCoreMLOptions
    ) -> URL? {
        guard let url = coreMLCacheDirectory(
            forModelAt: modelURL,
            ortVersion: ortVersion,
            resolvedOptions: resolvedOptions
        ) else { return nil }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? url : nil
        }

        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - SHA-256 helpers

    static func sha256OfFile(at url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            _ = buffer.withUnsafeBytes { ptr in
                CC_SHA256_Update(&ctx, ptr.baseAddress, CC_LONG(count))
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &ctx)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256OfString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "00000000" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum BGIInferenceSessionError: LocalizedError, Equatable {
    case allAttemptsFailed([String])

    var errorDescription: String? {
        switch self {
        case let .allAttemptsFailed(diagnostics):
            "All inference session creation attempts failed: \(diagnostics.joined(separator: " | "))"
        }
    }
}
#endif
