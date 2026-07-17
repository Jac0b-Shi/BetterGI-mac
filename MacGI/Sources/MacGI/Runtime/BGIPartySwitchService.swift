import Foundation

struct BGIPartySwitchConfig: Sendable {
    var returnMainUIMaxRetries: Int = 8
    var returnMainUIRetryIntervalMs: UInt64 = 900
    var openPartySetupMaxAttempts: Int = 2
    var partySetupCheckIntervalMs: Int = 600
    var partySetupCheckRetries: Int = 7
    var selectConfirmDelayMs: Int = 200
    var confirmRetryMax: Int = 10
    var confirmRetryIntervalMs: Int = 500
    var pageScrollMax: Int = 16
    var pageScrollDelayMs: Int = 400
    var pageBottomThreshold: Double = 777
    var ocrTopOffset: Double = 80

    static let `default` = BGIPartySwitchConfig()
}

/// Upstream `SwitchPartyTask` port: returns to main UI, opens party setup,
/// finds PartyBtnChooseView, OCRs team names from the selection list with
/// regex matching, pages through the list, and confirms when the target team
/// is found or scrolls past the last entry.
final class BGIPartySwitchService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias OCRProvider = @MainActor (CaptureImageFrame, CGRect) async throws -> String

    private let captureFrameProvider: CaptureFrameProvider
    private let ocrProvider: OCRProvider?
    private let inputHandler: InputHandler
    private let config: BGIPartySwitchConfig
    private let templateEngine = TemplateMatchingRecognitionEngine()
    private let mainUIChecker = BGIMainUIStatusChecker()

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: @escaping CaptureFrameProvider,
        ocrProvider: OCRProvider? = nil,
        config: BGIPartySwitchConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.ocrProvider = ocrProvider
        self.config = config
    }

    func switchParty(to partyName: String) async throws -> Bool {
        // 1. Return to main UI
        let returnService = BGIReturnMainUIService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            config: BGIReturnMainUIConfig(
                maxEscapeAttempts: config.returnMainUIMaxRetries,
                escapeWaitMs: config.returnMainUIRetryIntervalMs,
                finalKeyWaitMs: 500
            )
        )
        try await returnService.returnToMainUI()
        try await sleep(200)

        // 2. Open party setup screen
        for _ in 1...config.openPartySetupMaxAttempts {
            await perform(.keyPress(key: KeyBindingsConfig.bgiDefault.key(for: .openPartySetupScreen).keyCode ?? .l))
            for _ in 0..<config.partySetupCheckRetries {
                try await sleep(config.partySetupCheckIntervalMs)
                let checkFrame = try await captureFrameProvider()
                if isInPartyView(checkFrame) { break }
            }
        }
        try await sleep(500)

        // 3. Find PartyBtnChooseView → OCR current team name
        let partyFrame = try await captureFrameProvider()
        let chooseResults = templateEngine.recognize(
            imageFrame: partyFrame,
            objects: RecognitionObject.bgiPartyChooseViewObjects
        ).observations
        guard let chooseBtn = chooseResults.first(where: { $0.objectID.contains("PartyBtnChooseView") }) else {
            throw BGIPartySwitchError.cannotFindPartyUI
        }
        let chooseRect = chooseBtn.normalizedRect

        let frameW = Double(partyFrame.metadata.width)
        let frameH = Double(partyFrame.metadata.height)
        let scale = frameW / 1920.0

        // OCR current team name (right of choose button)
        if let ocr = ocrProvider {
            let nameRect = CGRect(
                x: chooseRect.maxX * frameW,
                y: chooseRect.minY * frameH,
                width: 350 * scale,
                height: chooseRect.height * frameH
            )
            let currentName = (try? await ocr(partyFrame, nameRect))?.cleanPartyName() ?? ""
            if isMatch(currentName, pattern: partyName) {
                await perform(.keyPress(key: .escape))
                try await sleep(500)
                try await returnService.returnToMainUI()
                return true
            }
        }

        // 4. Click party choose button → wait for PartyBtnDelete
        await perform(.mouseClick(button: .left, at: CGPoint(
            x: chooseRect.midX * frameW,
            y: chooseRect.midY * frameH
        )))
        try await sleep(config.selectConfirmDelayMs)

        for _ in 0..<5 {
            let checkFrame = try await captureFrameProvider()
            let deleteResults = templateEngine.recognize(
                imageFrame: checkFrame,
                objects: RecognitionObject.bgiPartyDeleteObjects
            ).observations
            if deleteResults.contains(where: { $0.objectID.contains("PartyBtnDelete") }) { break }
            try await sleep(config.partySetupCheckIntervalMs)
        }

        // 5. Scroll to top of team list
        await perform(.mouseClick(button: .left, at: CGPoint(x: 700 * scale, y: 125 * scale)))
        try await sleep(50)
        await perform(.mouseButtonDown(button: .left, at: CGPoint(x: 700 * scale, y: 200 * scale)))
        try await sleep(450)
        await perform(.mouseButtonUp(button: .left, at: CGPoint(x: 700 * scale, y: 125 * scale)))
        try await sleep(100)

        // 6. Page loop: OCR + regex match teams
        for i in 0..<config.pageScrollMax {
            let page = try await captureFrameProvider()
            let pw = Double(page.metadata.width)
            let ph = Double(page.metadata.height)
            let pScale = pw / 1920.0

            if i == 0 {
                await perform(.mouseClick(button: .left, at: CGPoint(x: 600 * pScale, y: 200 * pScale)))
                try await sleep(300)
            }

            if let ocr = ocrProvider {
                // OCR the team list area (below 80px top offset, up to the delete button area)
                let listRect = CGRect(
                    x: 0,
                    y: config.ocrTopOffset * pScale,
                    width: pw,
                    height: ph - config.ocrTopOffset * pScale
                )
                let ocrText = try? await ocr(page, listRect)
                let lines = ocrText?.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []

                if let matched = lines.first(where: { isMatch($0.cleanPartyName(), pattern: partyName) }) {
                    // Compute approximate Y from line index
                    let idx = (lines.firstIndex(of: matched) ?? 0)
                    let cy = config.ocrTopOffset * pScale + Double(idx + 1) * 40 * pScale
                    await perform(.mouseClick(button: .left, at: CGPoint(x: 400 * pScale, y: min(cy, ph * 0.9))))
                    try await sleep(config.selectConfirmDelayMs)
                    try await confirmPartySelection(page: page)
                    return true
                }

                // Bottom detection: if OCR text ends near bottom threshold, we're done
                if let lastY = ocrText?.range(of: "\n", options: .backwards).map({ _ in ph * 0.85 }) {
                    if lastY < config.pageBottomThreshold * pScale * 0.7 { break }
                }
            } else {
                // No OCR: just click the next team entry
                await perform(.mouseClick(button: .left, at: CGPoint(x: 400 * pScale, y: 200 + Double(i) * 50 * pScale)))
                try await sleep(config.selectConfirmDelayMs)
                try await confirmPartySelection(page: page)
                return true
            }

            // Scroll down to next page
            await perform(.mouseClick(button: .left, at: CGPoint(
                x: pw * 0.3,
                y: ph * 0.85
            )))
            try await sleep(config.pageScrollDelayMs)
        }

        try await returnService.returnToMainUI()
        return false
    }

    // MARK: - Private

    private func confirmPartySelection(page: CaptureImageFrame) async throws {
        let w = Double(page.metadata.width)
        let h = Double(page.metadata.height)
        await perform(.mouseClick(button: .left, at: CGPoint(x: w * 0.75, y: h * 0.5)))
        try await sleep(300)
        for _ in 0..<config.confirmRetryMax {
            let cf = try await captureFrameProvider()
            let dr = templateEngine.recognize(imageFrame: cf, objects: RecognitionObject.bgiPartyDeleteObjects).observations
            if dr.isEmpty { break }
            try await sleep(config.confirmRetryIntervalMs)
        }
        await perform(.mouseClick(button: .left, at: CGPoint(x: w * 0.85, y: h * 0.8)))
        try await sleep(500)
        let returnService = BGIReturnMainUIService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            config: BGIReturnMainUIConfig(maxEscapeAttempts: 3, escapeWaitMs: 500, finalKeyWaitMs: 300)
        )
        try await returnService.returnToMainUI()
    }

    private func isInPartyView(_ frame: CaptureImageFrame) -> Bool {
        templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiPartyChooseViewObjects)
            .observations.contains { $0.objectID.contains("PartyBtnChooseView") }
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func sleep(_ ms: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
}

enum BGIPartySwitchError: LocalizedError {
    case cannotFindPartyUI
    case cannotOpenPartyList
    case notFound

    var errorDescription: String? {
        switch self {
        case .cannotFindPartyUI: "找不到队伍配置界面"
        case .cannotOpenPartyList: "无法打开队伍选择列表"
        case .notFound: "未找到目标队伍"
        }
    }
}

// MARK: - Helpers

private func isMatch(_ text: String, pattern: String) -> Bool {
    (try? NSRegularExpression(pattern: pattern).firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text)
    )) != nil
}

private extension String {
    func cleanPartyName() -> String {
        replacing("\"", with: "")
            .replacing("\r\n", with: "")
            .replacing("\r", with: "")
            .split(separator: "\n").first.map(String.init) ?? self
            .trimmingCharacters(in: .whitespaces)
    }
}
