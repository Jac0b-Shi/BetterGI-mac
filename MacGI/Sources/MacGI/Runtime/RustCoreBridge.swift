import Darwin
import CoreGraphics
import Foundation

final class RustCoreBridge: CoreBridge {
    private static let autoSkipOptionClickObjectIDs = [
        "AutoSkip.OptionIconRo",
        "AutoSkip.DailyRewardIconRo",
        "AutoSkip.ExploreIconRo",
        "AutoSkip.DialogueOptionTextRo"
    ]

    let libraryPath: String
    let version: String

    private let libraryHandleRaw: UInt
    private let coreHandleRaw: UInt?
    private let destroyFn: DestroyFn
    private let startFn: StatusFn
    private let pauseFn: StatusFn
    private let submitFrameFn: SubmitFrameFn
    private let setFeatureEnabledFn: SetFeatureEnabledFn
    private let matchTemplateFn: MatchTemplateFn
    private let evaluateAutoPickFn: EvaluateAutoPickFn
    private let evaluateAutoSkipFn: EvaluateAutoSkipFn
    private var lastAutoPickMs: UInt64?
    private var lastAutoSkipExecuteMs: UInt64?
    private var lastAutoSkipPlayingMs: UInt64?

    var statusText: String {
        "Rust \(version)"
    }

    static func loadDefault() -> RustCoreBridge? {
        for path in candidateLibraryPaths() where FileManager.default.fileExists(atPath: path) {
            if let bridge = try? RustCoreBridge(libraryPath: path) {
                return bridge
            }
        }
        return nil
    }

    init(libraryPath: String) throws {
        guard let libraryHandle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw RustCoreBridgeError.loadFailed(String(cString: dlerror()))
        }

        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(libraryHandle, name) else {
                throw RustCoreBridgeError.missingSymbol(name)
            }
            return unsafeBitCast(pointer, to: type)
        }

        let createFn = try symbol("macgi_core_create", as: CreateFn.self)
        let destroyFn = try symbol("macgi_core_destroy", as: DestroyFn.self)
        let versionFn = try symbol("macgi_core_version", as: VersionFn.self)

        self.libraryPath = libraryPath
        libraryHandleRaw = UInt(bitPattern: libraryHandle)
        self.destroyFn = destroyFn
        startFn = try symbol("macgi_core_start", as: StatusFn.self)
        pauseFn = try symbol("macgi_core_pause", as: StatusFn.self)
        submitFrameFn = try symbol("macgi_core_submit_frame", as: SubmitFrameFn.self)
        setFeatureEnabledFn = try symbol("macgi_core_set_feature_enabled", as: SetFeatureEnabledFn.self)
        matchTemplateFn = try symbol("macgi_core_match_template", as: MatchTemplateFn.self)
        evaluateAutoPickFn = try symbol("macgi_core_evaluate_auto_pick", as: EvaluateAutoPickFn.self)
        evaluateAutoSkipFn = try symbol("macgi_core_evaluate_auto_skip", as: EvaluateAutoSkipFn.self)
        coreHandleRaw = createFn(nil as RustEventCallback?, nil).map { UInt(bitPattern: $0) }
        version = versionFn().map { String(cString: $0) } ?? "unknown"
    }

    deinit {
        if let coreHandleRaw {
            destroyFn(UnsafeMutableRawPointer(bitPattern: coreHandleRaw))
        }
        dlclose(UnsafeMutableRawPointer(bitPattern: libraryHandleRaw))
    }

    @MainActor
    func start() {
        guard let coreHandle = coreHandlePointer else { return }
        _ = startFn(coreHandle)
    }

    @MainActor
    func pause() {
        guard let coreHandle = coreHandlePointer else { return }
        _ = pauseFn(coreHandle)
    }

    @MainActor
    func heartbeat() {
        guard let coreHandle = coreHandlePointer else { return }
        var frame = FFIMacGIFrame(
            data: nil,
            dataLen: 0,
            width: 1,
            height: 1,
            stride: 4,
            pixelFormat: 0x42475241,
            timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
        _ = withUnsafePointer(to: &frame) { framePointer in
            submitFrameFn(coreHandle, UnsafeRawPointer(framePointer))
        }
    }

    @MainActor
    func setFeature(_ featureID: String, enabled: Bool) {
        guard let coreHandle = coreHandlePointer else { return }
        featureID.withCString { pointer in
            _ = setFeatureEnabledFn(coreHandle, pointer, enabled ? 1 : 0)
        }
    }

    func makeBigMapSiftBridge() -> BGIBigMapSiftBridge? {
        guard let coreHandle = coreHandlePointer,
              let libraryHandle = UnsafeMutableRawPointer(bitPattern: libraryHandleRaw) else {
            return nil
        }
        return try? BGIBigMapSiftBridge(coreHandle: coreHandle, dylibHandle: libraryHandle)
    }

    @MainActor
    func submit(frame: CapturedFrame) {
        guard let coreHandle = coreHandlePointer else { return }
        var ffiFrame = FFIMacGIFrame(
            data: nil,
            dataLen: 0,
            width: UInt32(max(0, frame.width)),
            height: UInt32(max(0, frame.height)),
            stride: UInt32(max(0, frame.bytesPerRow)),
            pixelFormat: UInt32(frame.pixelFormat),
            timestampNs: UInt64(frame.timestamp.timeIntervalSince1970 * 1_000_000_000)
        )
        _ = withUnsafePointer(to: &ffiFrame) { framePointer in
            submitFrameFn(coreHandle, UnsafeRawPointer(framePointer))
        }
    }

    @MainActor
    func evaluateAutoPickDecision(
        frame: CapturedFrame,
        observations: [RecognitionObservation],
        recognitionObjects: [RecognitionObject],
        keyBindings: KeyBindingsConfig
    ) -> TriggerDecision? {
        let autoPickObservations = observations.filter { $0.objectID.hasPrefix("AutoPick.") }
        let fThreshold = recognitionObjects.first(where: { $0.id == "AutoPick.FRo" })?.threshold ?? 0.8
        let nowMs = UInt64(frame.timestamp.timeIntervalSince1970 * 1000)

        return withFFIObservations(autoPickObservations) { ffiObservations in
            let config = FFIAutoPickConfig(
                enabled: 1,
                cooldownMs: 0,
                whitelist: FFIStringList(items: nil, count: 0),
                blacklist: FFIStringList(items: nil, count: 0),
                fuzzyBlacklist: FFIStringList(items: nil, count: 0),
                allowWhenWhitelistEmpty: 1,
                minFIconConfidence: Float(fThreshold),
                minOcrConfidence: 0.5
            )
            var request = FFIAutoPickRequest(
                frameIndex: frame.frameIndex,
                nowMs: nowMs,
                observations: nil,
                observationCount: UInt32(ffiObservations.count),
                config: config,
                hasLastPickMs: lastAutoPickMs == nil ? 0 : 1,
                lastPickMs: lastAutoPickMs ?? 0
            )
            var decision = FFIAutoPickDecision()

            let status: Int32
            if ffiObservations.isEmpty {
                status = withUnsafePointer(to: &request) { requestPointer in
                    withUnsafeMutablePointer(to: &decision) { decisionPointer in
                        evaluateAutoPickFn(
                            UnsafeRawPointer(requestPointer),
                            UnsafeMutableRawPointer(decisionPointer)
                        )
                    }
                }
            } else {
                status = ffiObservations.withUnsafeBufferPointer { buffer in
                    request.observations = buffer.baseAddress
                    return withUnsafePointer(to: &request) { requestPointer in
                        withUnsafeMutablePointer(to: &decision) { decisionPointer in
                            evaluateAutoPickFn(
                                UnsafeRawPointer(requestPointer),
                                UnsafeMutableRawPointer(decisionPointer)
                            )
                        }
                    }
                }
            }

            guard status == 0 else { return nil }
            if decision.hasUpdatedLastPickMs != 0 {
                lastAutoPickMs = decision.updatedLastPickMs
            }

            guard decision.hasGameAction else { return nil }
            guard decision.gameAction == FFIGameAction.pickUpOrInteract.rawValue,
                  let inputAction = keyBindings.inputAction(for: .pickUpOrInteract) else {
                return nil
            }

            let pickupConfidence = autoPickObservations
                .first(where: { $0.objectID == "AutoPick.FRo" })?
                .confidence ?? 0
            return TriggerDecision(
                id: "RustAutoPick-\(frame.frameIndex)",
                triggerID: .autoPick,
                priority: 30,
                reason: "Rust AutoPick: PickRo 命中，输出 PickUpOrInteract -> \(keyBindings.key(for: .pickUpOrInteract).displayName)",
                confidence: pickupConfidence,
                actions: [inputAction],
                observationIDs: autoPickObservations.map(\.id),
                timestamp: frame.timestamp
            )
        }
    }

    @MainActor
    func evaluateAutoSkipDecision(
        frame: CapturedFrame,
        observations: [RecognitionObservation],
        recognitionObjects: [RecognitionObject],
        currentGameUiCategory: GameUiCategory,
        keyBindings: KeyBindingsConfig
    ) -> TriggerDecision? {
        let autoSkipObservations = observations.filter {
            $0.objectID.hasPrefix("AutoSkip.") || $0.objectID == "AutoPick.ChatPickRo"
        }
        let minConfidence = recognitionObjects
            .filter { $0.id.hasPrefix("AutoSkip.") || $0.id == "AutoPick.ChatPickRo" }
            .map(\.threshold)
            .min() ?? 0.8
        let nowMs = UInt64(frame.timestamp.timeIntervalSince1970 * 1000)

        return withFFIObservations(autoSkipObservations) { ffiObservations in
            let config = FFIAutoSkipConfig(
                enabled: 1,
                quicklySkipConversationsEnabled: 1,
                clickOptionMode: FFIAutoSkipClickOptionMode.first.rawValue,
                closePopupPagedEnabled: 1,
                submitGoodsEnabled: 1,
                autoGetDailyRewardsEnabled: 1,
                autoReExploreEnabled: 1,
                autoHangoutEventEnabled: 0,
                autoHangoutPressSkipEnabled: 1,
                minObservationConfidence: Float(minConfidence)
            )
            var request = FFIAutoSkipRequest(
                frameIndex: frame.frameIndex,
                nowMs: nowMs,
                isTalkUi: currentGameUiCategory == .talk ? 1 : 0,
                observations: nil,
                observationCount: UInt32(ffiObservations.count),
                config: config,
                hasPrevExecuteMs: lastAutoSkipExecuteMs == nil ? 0 : 1,
                prevExecuteMs: lastAutoSkipExecuteMs ?? 0,
                hasPrevPlayingMs: lastAutoSkipPlayingMs == nil ? 0 : 1,
                prevPlayingMs: lastAutoSkipPlayingMs ?? 0
            )
            var decision = FFIAutoSkipDecision()

            let status: Int32
            if ffiObservations.isEmpty {
                status = withUnsafePointer(to: &request) { requestPointer in
                    withUnsafeMutablePointer(to: &decision) { decisionPointer in
                        evaluateAutoSkipFn(
                            UnsafeRawPointer(requestPointer),
                            UnsafeMutableRawPointer(decisionPointer)
                        )
                    }
                }
            } else {
                status = ffiObservations.withUnsafeBufferPointer { buffer in
                    request.observations = buffer.baseAddress
                    return withUnsafePointer(to: &request) { requestPointer in
                        withUnsafeMutablePointer(to: &decision) { decisionPointer in
                            evaluateAutoSkipFn(
                                UnsafeRawPointer(requestPointer),
                                UnsafeMutableRawPointer(decisionPointer)
                            )
                        }
                    }
                }
            }

            guard status == 0 else { return nil }
            if decision.hasUpdatedPrevExecuteMs != 0 {
                lastAutoSkipExecuteMs = decision.updatedPrevExecuteMs
            }
            if decision.hasUpdatedPrevPlayingMs != 0 {
                lastAutoSkipPlayingMs = decision.updatedPrevPlayingMs
            }

            guard let action = FFIAutoSkipAction(rawValue: decision.action),
                  action != .none,
                  let inputAction = autoSkipInputAction(
                    for: action,
                    targetObservationIndex: decision.hasTargetObservationIndex == 0
                        ? nil
                        : Int(decision.targetObservationIndex),
                    observations: autoSkipObservations,
                    frame: frame,
                    keyBindings: keyBindings
                  ) else {
                return nil
            }

            let observationIDs = autoSkipObservationIDs(
                for: action,
                targetObservationIndex: decision.hasTargetObservationIndex == 0
                    ? nil
                    : Int(decision.targetObservationIndex),
                observations: autoSkipObservations
            )

            return TriggerDecision(
                id: "RustAutoSkip-\(frame.frameIndex)",
                triggerID: .autoSkip,
                priority: 20,
                reason: autoSkipReason(for: action, keyBindings: keyBindings, observationIDs: observationIDs),
                confidence: Double(decision.confidence),
                actions: [inputAction],
                observationIDs: observationIDs,
                timestamp: frame.timestamp
            )
        }
    }

    func recognizeTemplates(
        imageFrame: CaptureImageFrame,
        objects: [RecognitionObject]
    ) -> TemplateRecognitionReport? {
        let startedAt = Date()
        let templateObjects = objects.filter {
            $0.recognitionType == .templateMatch && $0.templateAssetName != nil
        }
        guard !templateObjects.isEmpty else {
            return TemplateRecognitionReport(observations: [], objectCount: 0, matchedCount: 0, costMs: 0, backendName: "rustDylib")
        }
        guard let framePixels = Self.bgraData(from: imageFrame.cgImage) else {
            return nil
        }

        let observations = templateObjects.flatMap { object in
            templateObservations(for: object, imageFrame: imageFrame, framePixels: framePixels)
        }
        return TemplateRecognitionReport(
            observations: observations,
            objectCount: templateObjects.count,
            matchedCount: observations.count,
            costMs: Date().timeIntervalSince(startedAt) * 1000,
            backendName: "rustDylib"
        )
    }

    private func templateObservations(
        for object: RecognitionObject,
        imageFrame: CaptureImageFrame,
        framePixels: Data
    ) -> [RecognitionObservation] {
        let imageWidth = imageFrame.cgImage.width
        let imageHeight = imageFrame.cgImage.height
        guard imageWidth > 0,
              imageHeight > 0,
              imageWidth <= Int(UInt32.max / 4),
              imageHeight <= Int(UInt32.max) else {
            return []
        }
        guard let templateData = try? BGIAssetResolver.scaledTemplatePNGData(for: object, frameWidth: imageWidth),
              !templateData.isEmpty else {
            return []
        }

        let bytesPerRow = imageWidth * 4
        let capacity = Self.outputCapacity(for: object)
        var output = [FFITemplateMatchObservation](
            repeating: FFITemplateMatchObservation(),
            count: capacity
        )
        var outputCount: UInt32 = 0
        let roi = Self.pixelROI(for: object.regionOfInterest, width: imageWidth, height: imageHeight)

        let status = framePixels.withUnsafeBytes { frameBuffer in
            templateData.withUnsafeBytes { templateBuffer in
                guard let frameBase = frameBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let templateBase = templateBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return Int32(-3)
                }

                let ffiFrame = FFIMacGIFrame(
                    data: frameBase,
                    dataLen: UInt(framePixels.count),
                    width: UInt32(imageWidth),
                    height: UInt32(imageHeight),
                    stride: UInt32(bytesPerRow),
                    pixelFormat: 0x42475241,
                    timestampNs: Self.timestampNanoseconds(imageFrame.metadata.timestamp)
                )
                var request = FFITemplateMatchRequest(
                    frame: ffiFrame,
                    templateData: templateBase,
                    templateLen: UInt(templateData.count),
                    threshold: Float(object.threshold),
                    use3Channels: object.use3Channels ? 1 : 0,
                    matchMode: object.templateMatchMode.ffiRawValue,
                    useMask: object.useMask ? 1 : 0,
                    maskB: Self.clampedColorChannel(object.maskColor.b),
                    maskG: Self.clampedColorChannel(object.maskColor.g),
                    maskR: Self.clampedColorChannel(object.maskColor.r),
                    maskA: Self.clampedColorChannel(object.maskColor.a),
                    maxMatchCount: Int32(clamping: object.maxMatchCount),
                    useBinaryMatch: object.useBinaryMatch ? 1 : 0,
                    binaryThreshold: Int32(clamping: object.binaryThreshold),
                    hasROI: roi == nil ? 0 : 1,
                    roiX: roi?.x ?? 0,
                    roiY: roi?.y ?? 0,
                    roiWidth: roi?.width ?? 0,
                    roiHeight: roi?.height ?? 0
                )

                return withUnsafePointer(to: &request) { requestPointer in
                    output.withUnsafeMutableBufferPointer { outputBuffer in
                        withUnsafeMutablePointer(to: &outputCount) { outputCountPointer in
                            let outputPointer = outputBuffer.baseAddress.map { UnsafeMutableRawPointer($0) }
                            return matchTemplateFn(
                                UnsafeRawPointer(requestPointer),
                                outputPointer,
                                UInt32(outputBuffer.count),
                                outputCountPointer
                            )
                        }
                    }
                }
            }
        }
        guard status == 0, outputCount > 0 else { return [] }

        let matches = output.prefix(Int(outputCount))
        return matches.enumerated().map { index, match in
            let suffix = matches.count == 1 ? "" : "-\(index)"
            return RecognitionObservation(
                id: "\(object.id)-\(imageFrame.metadata.frameIndex)\(suffix)",
                objectID: object.id,
                objectName: object.name ?? object.id,
                recognitionType: object.recognitionType,
                normalizedRect: CGRect(
                    x: Double(match.normalizedX),
                    y: Double(match.normalizedY),
                    width: Double(match.normalizedWidth),
                    height: Double(match.normalizedHeight)
                ),
                confidence: Double(match.confidence),
                text: nil,
                frameIndex: imageFrame.metadata.frameIndex,
                timestamp: imageFrame.metadata.timestamp
            )
        }
    }

    private static func candidateLibraryPaths() -> [String] {
        let env = ProcessInfo.processInfo.environment["MACGI_CORE_DYLIB"].map { [$0] } ?? []
        let cwd = FileManager.default.currentDirectoryPath
        let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path
        let resourceDir = Bundle.main.resourceURL?.path
        let local = [
            "\(cwd)/macgi-core/target/debug/libmacgi_core.dylib",
            "\(cwd)/macgi-core/target/release/libmacgi_core.dylib"
        ]
        let bundle = [executableDir, resourceDir]
            .compactMap { $0 }
            .flatMap { dir in
                [
                    "\(dir)/libmacgi_core.dylib",
                    "\(dir)/Frameworks/libmacgi_core.dylib",
                    "\(dir)/../Frameworks/libmacgi_core.dylib"
                ]
            }
        return Array(NSOrderedSet(array: env + local + bundle)) as? [String] ?? env + local + bundle
    }

    private var coreHandlePointer: UnsafeMutableRawPointer? {
        coreHandleRaw.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
    }

    private static func bgraData(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue
              ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(pixels)
    }

    private static func pixelROI(for roi: RecognitionROI?, width: Int, height: Int) -> TemplateMatchPixelROI? {
        guard let roi else { return nil }
        let normalized = roi.normalizedRect()
        let minX = max(0, Int(floor(normalized.minX * Double(width))))
        let minY = max(0, Int(floor(normalized.minY * Double(height))))
        let maxX = min(width, Int(ceil(normalized.maxX * Double(width))))
        let maxY = min(height, Int(ceil(normalized.maxY * Double(height))))
        guard maxX > minX, maxY > minY else { return nil }
        return TemplateMatchPixelROI(
            x: Int32(clamping: minX),
            y: Int32(clamping: minY),
            width: Int32(clamping: maxX - minX),
            height: Int32(clamping: maxY - minY)
        )
    }

    private static func outputCapacity(for object: RecognitionObject) -> Int {
        if object.maxMatchCount > 1 {
            return min(object.maxMatchCount, 64)
        }
        return 1
    }

    private static func timestampNanoseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970 * 1_000_000_000))
    }

    private static func clampedColorChannel(_ value: Double) -> UInt32 {
        guard value.isFinite else { return 0 }
        return UInt32(max(0, min(255, value.rounded())))
    }

    private func withFFIObservations<T>(
        _ observations: [RecognitionObservation],
        _ body: ([FFIRecognitionObservation]) -> T
    ) -> T {
        var allocated: [UnsafeMutablePointer<CChar>] = []
        allocated.reserveCapacity(observations.count * 3)
        defer {
            for pointer in allocated {
                free(pointer)
            }
        }

        func makeCString(_ value: String?) -> UnsafePointer<CChar>? {
            guard let value, let pointer = strdup(value) else { return nil }
            allocated.append(pointer)
            return UnsafePointer(pointer)
        }

        let ffiObservations = observations.map { observation in
            FFIRecognitionObservation(
                objectID: makeCString(observation.objectID),
                objectName: makeCString(observation.objectName),
                recognitionType: observation.recognitionType.ffiRawValue,
                confidence: Float(observation.confidence),
                text: makeCString(observation.text),
                hasNormalizedRect: 1,
                normalizedX: Float(observation.normalizedRect.minX),
                normalizedY: Float(observation.normalizedRect.minY),
                normalizedWidth: Float(observation.normalizedRect.width),
                normalizedHeight: Float(observation.normalizedRect.height)
            )
        }
        return body(ffiObservations)
    }

    private func autoSkipInputAction(
        for action: FFIAutoSkipAction,
        targetObservationIndex: Int?,
        observations: [RecognitionObservation],
        frame: CapturedFrame,
        keyBindings: KeyBindingsConfig
    ) -> InputAction? {
        switch action {
        case .none:
            return nil
        case .pressSpace:
            return .keyPress(key: .space)
        case .pressInteract:
            return keyBindings.inputAction(for: .pickUpOrInteract)
        case .pressEscape:
            return .keyPress(key: .escape)
        case .clickOption:
            return clickAction(
                forAnyOf: Self.autoSkipOptionClickObjectIDs,
                targetObservationIndex: targetObservationIndex,
                observations: observations,
                frame: frame
            )
        case .clickExclamation:
            return clickAction(
                for: "AutoSkip.ExclamationIconRo",
                targetObservationIndex: targetObservationIndex,
                observations: observations,
                frame: frame
            )
        case .clickSubmitGoods:
            return clickAction(
                for: "AutoSkip.SubmitGoodsRo",
                targetObservationIndex: targetObservationIndex,
                observations: observations,
                frame: frame
            )
        case .clickHangoutSkip:
            return clickAction(
                for: "AutoSkip.HangoutSkipRo",
                targetObservationIndex: targetObservationIndex,
                observations: observations,
                frame: frame
            )
        }
    }

    private func clickAction(
        for objectID: String,
        targetObservationIndex: Int?,
        observations: [RecognitionObservation],
        frame: CapturedFrame
    ) -> InputAction? {
        clickAction(
            forAnyOf: [objectID],
            targetObservationIndex: targetObservationIndex,
            observations: observations,
            frame: frame
        )
    }

    private func clickAction(
        forAnyOf objectIDs: [String],
        targetObservationIndex: Int?,
        observations: [RecognitionObservation],
        frame: CapturedFrame
    ) -> InputAction? {
        let acceptedIDs = Set(objectIDs)
        let indexedObservation = targetObservationIndex.flatMap { index -> RecognitionObservation? in
            guard observations.indices.contains(index),
                  acceptedIDs.contains(observations[index].objectID) else {
                return nil
            }
            return observations[index]
        }
        guard let observation = indexedObservation ?? observations.first(where: { acceptedIDs.contains($0.objectID) }) else {
            return nil
        }
        guard let point = InputTargetResolver.screenPoint(for: observation.normalizedRect, in: frame) else {
            return nil
        }
        return .leftClick(at: point)
    }

    private func autoSkipObservationIDs(
        for action: FFIAutoSkipAction,
        targetObservationIndex: Int?,
        observations: [RecognitionObservation]
    ) -> [String] {
        let objectID: String? = switch action {
        case .none, .pressSpace:
            nil
        case .pressInteract:
            "AutoPick.ChatPickRo"
        case .pressEscape:
            "AutoSkip.PageCloseRo"
        case .clickOption:
            nil
        case .clickExclamation:
            "AutoSkip.ExclamationIconRo"
        case .clickSubmitGoods:
            "AutoSkip.SubmitGoodsRo"
        case .clickHangoutSkip:
            "AutoSkip.HangoutSkipRo"
        }
        guard let objectID else {
            if action == .clickOption,
               let targetObservationIndex,
               observations.indices.contains(targetObservationIndex),
               Self.autoSkipOptionClickObjectIDs.contains(observations[targetObservationIndex].objectID) {
                return [observations[targetObservationIndex].id]
            }
            if action == .clickOption {
                return observations
                    .filter { Self.autoSkipOptionClickObjectIDs.contains($0.objectID) }
                    .map(\.id)
            }
            return observations.map(\.id)
        }
        if let targetObservationIndex,
           observations.indices.contains(targetObservationIndex),
           observations[targetObservationIndex].objectID == objectID {
            return [observations[targetObservationIndex].id]
        }
        return observations.filter { $0.objectID == objectID }.map(\.id)
    }

    private func autoSkipReason(
        for action: FFIAutoSkipAction,
        keyBindings: KeyBindingsConfig,
        observationIDs: [String]
    ) -> String {
        switch action {
        case .none:
            return "Rust AutoSkip: no action"
        case .pressSpace:
            return "Rust AutoSkip: Talk UI，按 QuicklySkipConversationsEnabled 发送 Space"
        case .pressInteract:
            return "Rust AutoSkip: ChatPickRo 命中，发送 \(keyBindings.key(for: .pickUpOrInteract).displayName)"
        case .pressEscape:
            return "Rust AutoSkip: PageCloseRo 命中，发送 Escape 关闭弹页"
        case .clickOption:
            if observationIDs.contains(where: { $0.hasPrefix("AutoSkip.DailyRewardIconRo") }) {
                return "Rust AutoSkip: DailyRewardIconRo 命中，点击每日委托选项"
            }
            if observationIDs.contains(where: { $0.hasPrefix("AutoSkip.ExploreIconRo") }) {
                return "Rust AutoSkip: ExploreIconRo 命中，点击探索派遣选项"
            }
            if observationIDs.contains(where: { $0.hasPrefix("AutoSkip.DialogueOptionTextRo") }) {
                return "Rust AutoSkip: 选项文字命中，点击对话选项"
            }
            return "Rust AutoSkip: OptionIconRo 命中，点击对话选项"
        case .clickExclamation:
            return "Rust AutoSkip: ExclamationIconRo 命中，点击感叹号选项"
        case .clickSubmitGoods:
            return "Rust AutoSkip: SubmitGoodsRo 命中，点击提交物品"
        case .clickHangoutSkip:
            return "Rust AutoSkip: HangoutSkipRo 命中，点击邀约跳过"
        }
    }

}

private enum RustCoreBridgeError: LocalizedError {
    case loadFailed(String)
    case missingSymbol(String)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(message):
            "Failed to load macgi-core dylib: \(message)"
        case let .missingSymbol(name):
            "Missing macgi-core symbol: \(name)"
        }
    }
}

private typealias RustEventCallback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
private typealias CreateFn = @convention(c) (RustEventCallback?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias DestroyFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias StatusFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias SubmitFrameFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int32
private typealias SetFeatureEnabledFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32) -> Int32
private typealias MatchTemplateFn = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
private typealias EvaluateAutoPickFn = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32
private typealias EvaluateAutoSkipFn = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32
private typealias VersionFn = @convention(c) () -> UnsafePointer<CChar>?

private struct TemplateMatchPixelROI {
    var x: Int32
    var y: Int32
    var width: Int32
    var height: Int32
}

private struct FFIMacGIFrame {
    var data: UnsafePointer<UInt8>?
    var dataLen: UInt
    var width: UInt32
    var height: UInt32
    var stride: UInt32
    var pixelFormat: UInt32
    var timestampNs: UInt64
}

private struct FFITemplateMatchRequest {
    var frame: FFIMacGIFrame
    var templateData: UnsafePointer<UInt8>?
    var templateLen: UInt
    var threshold: Float
    var use3Channels: Int32
    var matchMode: Int32
    var useMask: Int32
    var maskB: UInt32
    var maskG: UInt32
    var maskR: UInt32
    var maskA: UInt32
    var maxMatchCount: Int32
    var useBinaryMatch: Int32
    var binaryThreshold: Int32
    var hasROI: Int32
    var roiX: Int32
    var roiY: Int32
    var roiWidth: Int32
    var roiHeight: Int32
}

private struct FFITemplateMatchObservation {
    var confidence: Float = 0
    var normalizedX: Float = 0
    var normalizedY: Float = 0
    var normalizedWidth: Float = 0
    var normalizedHeight: Float = 0
}

private struct FFICoreMetrics {
    var processingCostMs: Double = 0
    var captureCostMs: Double = 0
    var triggerCostMs: Double = 0
    var confidence: Double = 0
    var skippedTicks: UInt32 = 0
}

private struct FFIMacGIEvent {
    var kind: Int32
    var message: UnsafePointer<CChar>?
    var metrics: FFICoreMetrics
}

private struct FFIStringList {
    var items: UnsafePointer<UnsafePointer<CChar>?>?
    var count: UInt32
}

private struct FFIRecognitionObservation {
    var objectID: UnsafePointer<CChar>?
    var objectName: UnsafePointer<CChar>?
    var recognitionType: Int32
    var confidence: Float
    var text: UnsafePointer<CChar>?
    var hasNormalizedRect: Int32
    var normalizedX: Float
    var normalizedY: Float
    var normalizedWidth: Float
    var normalizedHeight: Float
}

private struct FFIAutoPickConfig {
    var enabled: Int32
    var cooldownMs: UInt64
    var whitelist: FFIStringList
    var blacklist: FFIStringList
    var fuzzyBlacklist: FFIStringList
    var allowWhenWhitelistEmpty: Int32
    var minFIconConfidence: Float
    var minOcrConfidence: Float
}

private struct FFIAutoPickRequest {
    var frameIndex: UInt64
    var nowMs: UInt64
    var observations: UnsafePointer<FFIRecognitionObservation>?
    var observationCount: UInt32
    var config: FFIAutoPickConfig
    var hasLastPickMs: Int32
    var lastPickMs: UInt64
}

private struct FFIAutoPickDecision {
    var kind: Int32 = 0
    var gameAction: Int32 = 0
    var logLevel: Int32 = 2
    var reasonCode: Int32 = 0
    var hasUpdatedLastPickMs: Int32 = 0
    var updatedLastPickMs: UInt64 = 0

    var hasGameAction: Bool {
        kind == FFIDecisionKind.gameAction.rawValue
        || kind == FFIDecisionKind.gameActionAndLog.rawValue
    }
}

private struct FFIAutoSkipConfig {
    var enabled: Int32
    var quicklySkipConversationsEnabled: Int32
    var clickOptionMode: Int32
    var closePopupPagedEnabled: Int32
    var submitGoodsEnabled: Int32
    var autoGetDailyRewardsEnabled: Int32
    var autoReExploreEnabled: Int32
    var autoHangoutEventEnabled: Int32
    var autoHangoutPressSkipEnabled: Int32
    var minObservationConfidence: Float
}

private struct FFIAutoSkipRequest {
    var frameIndex: UInt64
    var nowMs: UInt64
    var isTalkUi: Int32
    var observations: UnsafePointer<FFIRecognitionObservation>?
    var observationCount: UInt32
    var config: FFIAutoSkipConfig
    var hasPrevExecuteMs: Int32
    var prevExecuteMs: UInt64
    var hasPrevPlayingMs: Int32
    var prevPlayingMs: UInt64
}

private struct FFIAutoSkipDecision {
    var action: Int32 = 0
    var confidence: Float = 0
    var reasonCode: Int32 = 0
    var hasTargetObservationIndex: Int32 = 0
    var targetObservationIndex: UInt32 = 0
    var hasUpdatedPrevExecuteMs: Int32 = 0
    var updatedPrevExecuteMs: UInt64 = 0
    var hasUpdatedPrevPlayingMs: Int32 = 0
    var updatedPrevPlayingMs: UInt64 = 0
}

private enum FFIDecisionKind: Int32 {
    case none = 0
    case gameAction = 1
    case logOnly = 2
    case gameActionAndLog = 3
}

private enum FFIGameAction: Int32 {
    case none = 0
    case pickUpOrInteract = 1
}

private enum FFIAutoSkipClickOptionMode: Int32 {
    case first = 0
    case last = 1
    case random = 2
    case none = 3
}

private enum FFIAutoSkipAction: Int32 {
    case none = 0
    case pressSpace = 1
    case pressInteract = 2
    case pressEscape = 3
    case clickOption = 10
    case clickExclamation = 11
    case clickSubmitGoods = 12
    case clickHangoutSkip = 13
}

private extension RecognitionType {
    var ffiRawValue: Int32 {
        switch self {
        case .none: 0
        case .templateMatch: 1
        case .colorMatch: 2
        case .ocrMatch: 3
        case .ocr: 4
        case .colorRangeAndOcr: 5
        case .detect: 6
        }
    }
}

private extension TemplateMatchMode {
    var ffiRawValue: Int32 {
        switch self {
        case .sqDiffNormed: 1
        case .cCorrNormed: 3
        case .cCoeffNormed: 5
        }
    }
}
