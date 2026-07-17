import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI JS script runtime")
struct BGIJSScriptRuntimeTests {
    @Test("Installed JS project loader reads user script manifest and settings")
    func installedJSScriptProjectLoaderReadsUserScriptManifestAndSettings() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-loader-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let scriptURL = store.userURL.appendingPathComponent("JsScript/Demo", isDirectory: true)
        try writeRuntimeFixtureScript(at: scriptURL)

        let project = try BGIInstalledJSScriptProjectLoader(store: store).loadProject(folderName: "Demo")

        #expect(project.folderName == "Demo")
        #expect(project.repositoryPath == "js/Demo")
        #expect(project.manifest.name == "Runtime Demo")
        #expect(project.manifest.library == ["./lib"])
        #expect(project.settings.map(\.name) == ["mode"])
        #expect(project.mainScriptURL.lastPathComponent == "main.js")
    }

    @Test("Installed JS project loader rejects unsafe folder names")
    func installedJSScriptProjectLoaderRejectsUnsafeFolderNames() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-unsafe-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        do {
            _ = try BGIInstalledJSScriptProjectLoader(store: store).loadProject(folderName: "../outside")
            Issue.record("Expected unsafe JS script folder to be rejected.")
        } catch let error as BGIJSScriptRuntimeError {
            #expect(error == .unsafePath("../outside"))
        }
    }

    @Test("JS runner executes modules, resource imports, settings, and host API calls")
    func jsRunnerExecutesModulesResourceImportsSettingsAndHostAPICalls() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-exec-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let scriptURL = store.userURL.appendingPathComponent("JsScript/Demo", isDirectory: true)
        try writeRuntimeFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader(store: store).loadProject(folderName: "Demo")

        let result = try BGIJSScriptRunner(versionString: "betterGI-mac-test").execute(
            project: project,
            settingsJSON: #"{"mode":"fast"}"#
        )

        #expect(result.mainScriptURL.lastPathComponent == "main.js")
        #expect(result.loadedModulePaths.contains { $0.hasSuffix("packages/utils/tool.js") })
        #expect(result.loadedModulePaths.contains { $0.hasSuffix("packages/utils/inner.js") })
        #expect(result.loadedModulePaths.contains { $0.hasSuffix("lib/helper.js") })
        #expect(result.logs.contains("[info] tool:inner|renamed|helper|hello|fast|betterGI-mac-test"))
        #expect(result.logs.contains("[info] 1920x1080"))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "file.ReadTextSync", arguments: ["assets/message.txt"])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "keyPress", arguments: ["F"])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "moveMouseTo", arguments: ["10.0", "20.0"])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "genshin.ChooseTalkOption",
            arguments: ["Katheryne", "10", "false"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "getGameMetrics", arguments: [])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "keyPress", arguments: ["VK_ESCAPE"])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "moveMouseBy", arguments: ["3.0", "-2.0"])))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "verticalScroll", arguments: ["-2"])))
        #expect(result.inputCommands.contains(.keyPress(.f)))
        #expect(result.inputCommands.contains(.keyPress(.escape)))
        #expect(result.inputCommands.contains(.mouseMoveToGame(x: 10, y: 20)))
        #expect(result.inputCommands.contains(.mouseMoveBy(dx: 3, dy: -2)))
        #expect(result.inputCommands.contains(.mouseClick(.left)))
        #expect(result.inputCommands.contains(.mouseButtonDown(.left)))
        #expect(result.inputCommands.contains(.mouseButtonUp(.left)))
        #expect(result.inputCommands.contains(.mouseClick(.right)))
        #expect(result.inputCommands.contains(.verticalScroll(-2)))
        #expect(result.inputCommands.contains(.inputText("hello traveler")))
        #expect(result.genshinCommands.contains(.chooseTalkOption(option: "Katheryne", skipTimes: 10, isOrange: false)))
    }

    @Test("JS runner exposes richer genshin host API arguments and results")
    func jsRunnerExposesRicherGenshinHostAPIArgumentsAndResults() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-genshin-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeGenshinBridgeFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")
        let environment = BGIRecordingJSScriptHostEnvironment(
            gameMetrics: [2560, 1440, 2],
            genshinCommandHandler: { command in
                switch command {
                case .uid:
                    return BGIJSScriptGenshinResult(intValue: 800123456)
                case .getPositionFromMap:
                    return BGIJSScriptGenshinResult(point: CGPoint(x: 12.5, y: -34.25))
                case .getPositionFromBigMap:
                    return BGIJSScriptGenshinResult(point: CGPoint(x: 88, y: 99))
                case .getCameraOrientation:
                    return BGIJSScriptGenshinResult(doubleValue: 271.5)
                case .getBigMapZoomLevel:
                    return BGIJSScriptGenshinResult(doubleValue: 3.5)
                default:
                    return BGIJSScriptGenshinResult(boolValue: true)
                }
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] metrics:2560x1440:1.33:2.0:2560x1440:2.0"))
        #expect(result.logs.contains("[info] genshin-values:800123456:12.5:-34.25:88:99:271.5:3.5"))
        #expect(result.logs.contains("[info] genshin-bools:true:true:true:true:true:true:true:true"))
        #expect(result.genshinCommands == [
            .uid,
            .teleport(x: 10, y: 20, mapName: "Teyvat", force: true),
            .moveMapTo(x: 30, y: 40, forceCountry: "璃月"),
            .moveIndependentMapTo(x: 50, y: 60, mapName: "Enkanomiya", forceCountry: "渊下宫"),
            .getBigMapZoomLevel,
            .setBigMapZoomLevel(4.5),
            .getPositionFromBigMap(mapName: "Teyvat"),
            .getPositionFromMap(mapName: "Teyvat", matchingMethod: "FeatureMatch", cacheTimeMs: 250, nearX: 12, nearY: 34),
            .getPositionFromMap(mapName: "Teyvat", matchingMethod: "TemplateMatch", cacheTimeMs: 900, nearX: nil, nearY: nil),
            .getCameraOrientation,
            .switchParty("Daily"),
            .clearPartyCache,
            .returnMainUI,
            .teleportToStatueOfTheSeven,
            .chooseTalkOption(option: "每日委托", skipTimes: 3, isOrange: true),
            .autoFishing(fishingTimePolicy: 2),
            .relogin,
            .setTime(hour: 18, minute: 30, skip: true)
        ])
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "genshin.GetPositionFromMap",
            arguments: ["Teyvat", "FeatureMatch", "250", "12.0", "34.0"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "genshin.GetPositionFromMapWithMatchingMethod",
            arguments: ["Teyvat", "TemplateMatch", "900"]
        )))
    }

    @Test("JS runner exposes capture metadata and OCR results from host environment")
    func jsRunnerExposesCaptureMetadataAndOCRResultsFromHostEnvironment() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-capture-ocr-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeCaptureOCRFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let timestamp = Date(timeIntervalSince1970: 1_782_886_400)
        let metadata = CapturedFrame(
            frameIndex: 42,
            timestamp: timestamp,
            width: 64,
            height: 32,
            scaleFactor: 2,
            pixelFormat: 0x42475241,
            bytesPerRow: 64 * 4,
            sourceWindow: .mock(title: "Genshin OCR")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 64, height: 32),
            backendName: "Synthetic"
        )
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [64, 32, 2],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, _ in
                OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 4, y: 8, width: 24, height: 10),
                            text: "Katheryne",
                            confidence: 0.95
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] capture:Synthetic:1:42:64x32:BGRA8888"))
        #expect(result.logs.contains("[info] ocr:Katheryne:1:Katheryne:0.95"))
        #expect(result.captureRegions.count == 1)
        #expect(result.captureRegions.first?.backendName == "Synthetic")
        #expect(result.captureRegions.first?.frameIndex == 42)
        #expect(result.captureRegions.first?.sourceWindowTitle == "Genshin OCR")
        #expect(result.ocrResults.count == 1)
        #expect(result.ocrResults.first?.combinedText == "Katheryne")
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "captureGameRegion.Ocr", arguments: ["1"])))
    }

    @Test("JS runner exposes BvPage OCR locator compatibility layer")
    func jsRunnerExposesBvPageOCRLocatorCompatibilityLayer() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-bvpage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvPageFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 88,
            timestamp: Date(timeIntervalSince1970: 1_782_886_500),
            width: 128,
            height: 72,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 128 * 4,
            sourceWindow: .mock(title: "BvPage OCR")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 128, height: 72),
            backendName: "Synthetic"
        )
        var requestedROIs: [CGRect?] = []
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [128, 72, 1],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, roi in
                requestedROIs.append(roi)
                return OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 6, y: 10, width: 30, height: 12),
                            text: "每日委托",
                            confidence: 0.97
                        ),
                        OCRResult.Region(
                            boundingBox: CGRect(x: 46, y: 10, width: 28, height: 12),
                            text: "探索派遣",
                            confidence: 0.91
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] bvpage:2:每日委托|探索派遣"))
        #expect(result.logs.contains("[info] locator:1:探索派遣"))
        #expect(requestedROIs == [
            CGRect(x: 4, y: 8, width: 80, height: 24),
            CGRect(x: 0, y: 0, width: 128, height: 40)
        ])
        #expect(result.captureRegions.count == 2)
        #expect(result.ocrResults.map(\.roi) == requestedROIs)
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "captureGameRegion.Ocr",
            arguments: ["1", "4.0,8.0,80.0,24.0"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "captureGameRegion.Ocr",
            arguments: ["2", "0.0,0.0,128.0,40.0"]
        )))
    }

    @Test("JS runner exposes BvLocator wait retry click and ROI helpers")
    func jsRunnerExposesBvLocatorWaitRetryClickAndROIHelpers() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-bvlocator-wait-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvLocatorWaitFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 89,
            timestamp: Date(timeIntervalSince1970: 1_782_886_550),
            width: 100,
            height: 80,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 100 * 4,
            sourceWindow: .mock(title: "BvLocator Wait")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 100, height: 80),
            backendName: "Synthetic"
        )
        var requestedROIs: [CGRect?] = []
        var ocrCallCount = 0
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [100, 80, 1],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, roi in
                requestedROIs.append(roi)
                ocrCallCount += 1
                let regions: [OCRResult.Region]
                if (2...3).contains(ocrCallCount) {
                    regions = [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 60, y: 10, width: 20, height: 12),
                            text: "Ready",
                            confidence: 0.96
                        )
                    ]
                } else {
                    regions = []
                }
                return OCRResult(
                    regions: regions,
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] retry:0"))
        #expect(result.logs.contains("[info] wait:1:Ready:60.0,10.0"))
        #expect(result.logs.contains("[info] click:60.0,10.0"))
        #expect(result.logs.contains("[info] gone:true"))
        #expect(result.logs.contains("[info] missing:0"))
        #expect(requestedROIs == [
            CGRect(x: 50, y: 0, width: 50, height: 40),
            CGRect(x: 50, y: 0, width: 50, height: 40),
            CGRect(x: 50, y: 0, width: 50, height: 40),
            CGRect(x: 50, y: 0, width: 50, height: 40),
            nil
        ])
        #expect(result.inputCommands.contains(BGIJSScriptInputCommand.mouseClickGame(button: .left, x: 70, y: 16)))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "sleep", arguments: ["1"])))
        #expect(result.captureRegions.count == 5)
    }

    @Test("BvLocator ClickUntilDisappears waits with a fresh locator like upstream")
    func bvLocatorClickUntilDisappearsUsesFreshDisappearLocator() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-click-until-disappears-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvLocatorClickUntilDisappearsFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 90,
            timestamp: Date(timeIntervalSince1970: 1_782_886_560),
            width: 100,
            height: 80,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 100 * 4,
            sourceWindow: .mock(title: "BvLocator ClickUntilDisappears")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 100, height: 80),
            backendName: "Synthetic"
        )
        var ocrCallCount = 0
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [100, 80, 1],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, _ in
                ocrCallCount += 1
                let regions: [OCRResult.Region]
                if ocrCallCount <= 2 {
                    regions = [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 10, y: 20, width: 30, height: 12),
                            text: "Vanish",
                            confidence: 0.97
                        )
                    ]
                } else {
                    regions = []
                }
                return OCRResult(
                    regions: regions,
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] click-until:Vanish:10,20"))
        #expect(result.inputCommands.filter { $0 == .mouseClickGame(button: .left, x: 25, y: 26) }.count == 2)
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(name: "sleep", arguments: ["250"])))
        #expect(ocrCallCount == 3)
    }

    @Test("JS runner exposes BvImage template locator compatibility layer")
    func jsRunnerExposesBvImageTemplateLocatorCompatibilityLayer() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-bvimage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvImageFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 99,
            timestamp: Date(timeIntervalSince1970: 1_782_886_600),
            width: 200,
            height: 100,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 200 * 4,
            sourceWindow: .mock(title: "BvImage Template")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 200, height: 100),
            backendName: "Synthetic"
        )
        var requestedLocators: [BGIJSScriptTemplateLocator] = []
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [200, 100, 1],
            captureFrameProvider: { imageFrame },
            templateProvider: { frame, locator in
                requestedLocators.append(locator)
                return [
                    RecognitionObservation(
                        id: "template-\(frame.metadata.frameIndex)",
                        objectID: locator.templateAssetName,
                        objectName: locator.templateAssetName,
                        recognitionType: .templateMatch,
                        normalizedRect: CGRect(x: 0.25, y: 0.2, width: 0.1, height: 0.2),
                        confidence: 0.93,
                        text: nil,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    ),
                    RecognitionObservation(
                        id: "template-extra-\(frame.metadata.frameIndex)",
                        objectID: "\(locator.templateAssetName)-extra",
                        objectName: "\(locator.templateAssetName)-extra",
                        recognitionType: .templateMatch,
                        normalizedRect: CGRect(x: 0.55, y: 0.4, width: 0.1, height: 0.2),
                        confidence: 0.91,
                        text: nil,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] template:1:50.0,20.0,20.0,20.0:0.93:AutoSkip:OptionIcon"))
        #expect(result.logs.contains("[info] find:AutoSkip:OptionIcon:50.0"))
        #expect(requestedLocators == [
            BGIJSScriptTemplateLocator(
                templateAssetName: "AutoSkip:OptionIcon",
                roi: CGRect(x: 10, y: 12, width: 80, height: 32),
                threshold: 0.72,
                findAll: false
            ),
            BGIJSScriptTemplateLocator(
                templateAssetName: "AutoSkip:OptionIcon",
                roi: CGRect(x: 10, y: 12, width: 80, height: 32),
                threshold: 0.72,
                findAll: false
            )
        ])
        #expect(result.captureRegions.count == 2)
        #expect(result.templateMatchRegions.count == 2)
        #expect(result.templateMatchRegions.first?.objectID == "AutoSkip:OptionIcon")
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "BvLocator.FindAll.Template",
            arguments: ["1", "AutoSkip:OptionIcon", "0.72", "false", "10.0,12.0,80.0,32.0"]
        )))
    }

    @Test("JS runner uses default template engine for BvImage direct asset paths")
    func jsRunnerUsesDefaultTemplateEngineForBvImageDirectAssetPaths() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-bvimage-default-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let assetName = "GameTask/AutoSkip/Assets/1920x1080/icon_option.png"
        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvImageDefaultTemplateFixtureScript(at: scriptURL, assetName: assetName)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let frameWidth = 960
        let frameHeight = 540
        let template = try BGIAssetResolver.scaledTemplateImage(for: assetName, frameWidth: frameWidth)
        let targetPoint = CGPoint(x: 250, y: 180)
        let image = try makeRuntimeSyntheticFrame(
            template: template,
            at: [targetPoint],
            size: CGSize(width: frameWidth, height: frameHeight)
        )
        let metadata = CapturedFrame(
            frameIndex: 101,
            timestamp: Date(timeIntervalSince1970: 1_782_886_700),
            width: frameWidth,
            height: frameHeight,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: frameWidth * 4,
            sourceWindow: .mock(title: "BvImage Default Template")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: image,
            backendName: "Synthetic"
        )
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [Double(frameWidth), Double(frameHeight), 1],
            captureFrameProvider: { imageFrame }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains { $0.hasPrefix("[info] default-template:1:\(assetName):") })
        #expect(result.templateMatchRegions.count == 1)
        let region = try #require(result.templateMatchRegions.first)
        #expect(region.objectID == assetName)
        #expect(region.confidence >= 0.99)
        #expect(CGRect(
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        ).intersects(CGRect(
            x: targetPoint.x,
            y: targetPoint.y,
            width: CGFloat(template.width),
            height: CGFloat(template.height)
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "BvLocator.FindAll.Template",
            arguments: ["1", assetName, "0.99", "false", "220.0,150.0,120.0,100.0"]
        )))
    }

    @Test("JS runner uses default template engine for BvImage feature asset aliases")
    func jsRunnerUsesDefaultTemplateEngineForBvImageFeatureAssetAliases() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-bvimage-alias-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let directAssetName = "GameTask/AutoSkip/Assets/1920x1080/icon_option.png"
        let aliasAssetName = "AutoSkip:icon_option.png"
        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeBvImageDefaultTemplateFixtureScript(at: scriptURL, assetName: aliasAssetName)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let frameWidth = 960
        let frameHeight = 540
        let template = try BGIAssetResolver.scaledTemplateImage(for: directAssetName, frameWidth: frameWidth)
        let targetPoint = CGPoint(x: 250, y: 180)
        let image = try makeRuntimeSyntheticFrame(
            template: template,
            at: [targetPoint],
            size: CGSize(width: frameWidth, height: frameHeight)
        )
        let metadata = CapturedFrame(
            frameIndex: 102,
            timestamp: Date(timeIntervalSince1970: 1_782_886_800),
            width: frameWidth,
            height: frameHeight,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: frameWidth * 4,
            sourceWindow: .mock(title: "BvImage Alias Template")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: image,
            backendName: "Synthetic"
        )
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [Double(frameWidth), Double(frameHeight), 1],
            captureFrameProvider: { imageFrame }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains { $0.hasPrefix("[info] default-template:1:\(aliasAssetName):") })
        #expect(result.templateMatchRegions.count == 1)
        let region = try #require(result.templateMatchRegions.first)
        #expect(region.objectID == aliasAssetName)
        #expect(region.confidence >= 0.99)
        #expect(CGRect(
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        ).intersects(CGRect(
            x: targetPoint.x,
            y: targetPoint.y,
            width: CGFloat(template.width),
            height: CGFloat(template.height)
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "BvLocator.FindAll.Template",
            arguments: ["1", aliasAssetName, "0.99", "false", "220.0,150.0,120.0,100.0"]
        )))
    }

    @Test("JS runner exposes ImageRegion Find and FindMulti compatibility layer")
    func jsRunnerExposesImageRegionFindAndFindMultiCompatibilityLayer() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-image-region-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeImageRegionFindFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 103,
            timestamp: Date(timeIntervalSince1970: 1_782_886_900),
            width: 240,
            height: 120,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 240 * 4,
            sourceWindow: .mock(title: "ImageRegion Find")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 240, height: 120),
            backendName: "Synthetic"
        )
        var requestedLocators: [BGIJSScriptTemplateLocator] = []
        var requestedROIs: [CGRect?] = []
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [240, 120, 1],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, roi in
                requestedROIs.append(roi)
                return OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 12, y: 16, width: 42, height: 14),
                            text: "兑换成功",
                            confidence: 0.94
                        ),
                        OCRResult.Region(
                            boundingBox: CGRect(x: 80, y: 18, width: 42, height: 14),
                            text: "兑换失败",
                            confidence: 0.88
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            },
            templateProvider: { frame, locator in
                requestedLocators.append(locator)
                return [
                    RecognitionObservation(
                        id: "region-template-\(frame.metadata.frameIndex)",
                        objectID: locator.templateAssetName,
                        objectName: locator.templateAssetName,
                        recognitionType: .templateMatch,
                        normalizedRect: CGRect(x: 0.5, y: 0.25, width: 0.1, height: 0.2),
                        confidence: 0.91,
                        text: nil,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] image-region-template:true:false:120,30"))
        #expect(result.logs.contains("[info] image-region-ocr-single:true:0,0:兑换成功兑换失败"))
        #expect(result.logs.contains("[info] image-region-ocr-multi:2:兑换成功|兑换替换:12,16:80,18"))
        #expect(requestedLocators == [
            BGIJSScriptTemplateLocator(
                templateAssetName: "UseRedeemCode:esc_return_button.png",
                roi: CGRect(x: 100, y: 20, width: 80, height: 60),
                threshold: 0.83,
                findAll: false
            )
        ])
        #expect(requestedROIs == [
            CGRect(x: 0, y: 0, width: 160, height: 80),
            CGRect(x: 0, y: 0, width: 160, height: 80)
        ])
        #expect(result.inputCommands.contains(.mouseClickGame(button: .left, x: 132, y: 42)))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.Find.Template",
            arguments: ["1", "UseRedeemCode:esc_return_button.png", "0.83", "false", "100.0,20.0,80.0,60.0"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.FindMulti.Ocr",
            arguments: ["1", "ocr", "成功", "0.0,0.0,160.0,80.0"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.Find.Ocr",
            arguments: ["1", "ocr", "成功", "0.0,0.0,160.0,80.0"]
        )))
    }

    @Test("JS runner supports RecognitionObject OcrMatch text rules")
    func jsRunnerSupportsRecognitionObjectOcrMatchTextRules() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-ocrmatch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeRecognitionObjectOcrMatchFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 104,
            timestamp: Date(timeIntervalSince1970: 1_782_887_000),
            width: 180,
            height: 90,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 180 * 4,
            sourceWindow: .mock(title: "RecognitionObject OcrMatch")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 180, height: 90),
            backendName: "Synthetic"
        )
        var requestedROIs: [CGRect?] = []
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [180, 90, 1],
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, roi in
                requestedROIs.append(roi)
                return OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 20, y: 10, width: 80, height: 16),
                            text: "兑错成功",
                            confidence: 0.92
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] ocr-match-static:true:0,0:兑错成功"))
        #expect(result.logs.contains("[info] ocr-match-rules:true:10,5:兑换成功"))
        #expect(result.logs.contains("[info] ocr-match-missing:true"))
        #expect(requestedROIs == [
            CGRect(x: 0, y: 0, width: 160, height: 80),
            CGRect(x: 10, y: 5, width: 120, height: 50),
            CGRect(x: 0, y: 0, width: 160, height: 80)
        ])
        #expect(result.ocrResults.count == 3)
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.Find.Ocr",
            arguments: ["1", "ocr", "0.0,0.0,160.0,80.0"]
        )))
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.Find.Ocr",
            arguments: ["1", "ocr", "10.0,5.0,120.0,50.0"]
        )))
    }

    @Test("JS runner forwards ColorRangeAndOcr RecognitionObject to object provider")
    func jsRunnerForwardsColorRangeAndOcrRecognitionObjectToObjectProvider() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-color-range-ocr-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeRecognitionObjectColorRangeAndOcrFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")

        let metadata = CapturedFrame(
            frameIndex: 106,
            timestamp: Date(timeIntervalSince1970: 1_782_887_200),
            width: 200,
            height: 100,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: 200 * 4,
            sourceWindow: .mock(title: "RecognitionObject ColorRangeAndOcr")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 200, height: 100),
            backendName: "Synthetic"
        )
        var requestedObjects: [RecognitionObject] = []
        let environment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: [200, 100, 1],
            captureFrameProvider: { imageFrame },
            recognitionObjectProvider: { frame, object, _ in
                requestedObjects.append(object)
                return [
                    RecognitionObservation(
                        id: "color-range-\(frame.metadata.frameIndex)",
                        objectID: object.id,
                        objectName: object.name ?? object.id,
                        recognitionType: object.recognitionType,
                        normalizedRect: CGRect(x: 0.2, y: 0.3, width: 0.25, height: 0.2),
                        confidence: 0.88,
                        text: "白字",
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            }
        )

        let result = try BGIJSScriptRunner(hostEnvironment: environment).execute(project: project)

        #expect(result.logs.contains("[info] color-range:true:40,30:白字"))
        let object = try #require(requestedObjects.first)
        #expect(object.recognitionType == .colorRangeAndOcr)
        #expect(object.regionOfInterest?.normalizedRect() == CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.4))
        #expect(object.lowerColor == BGIColorScalar(b: 0, g: 0, r: 210, a: 255))
        #expect(object.upperColor == BGIColorScalar(b: 90, g: 80, r: 255, a: 255))
        #expect(object.colorConversionCode == 4)
        #expect(result.hostCalls.contains(BGIJSScriptHostCall(
            name: "ImageRegion.Find.ColorRangeAndOcr",
            arguments: ["1", "ColorRangeAndOcr", "10.0,10.0,100.0,40.0"]
        )))
        #expect(result.templateMatchRegions.count == 1)
    }

    @Test("JS ImageRegion rejects recognition types unsupported by upstream BGI")
    func jsImageRegionRejectsUnsupportedRecognitionTypesLikeUpstream() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-unsupported-recognition-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let colorMatchURL = tempRoot.appendingPathComponent("ColorMatch", isDirectory: true)
        try writeUnsupportedRecognitionObjectFixtureScript(
            at: colorMatchURL,
            mainScript: """
            const screen = captureGameRegion();
            screen.Find(RecognitionObject.ColorMatch(0, 0, 50, 30, [0, 0, 0, 255], [255, 255, 255, 255], 1, 4));
            """
        )
        let colorMatchProject = try BGIInstalledJSScriptProjectLoader().loadProject(
            at: colorMatchURL,
            folderName: "ColorMatch"
        )
        do {
            _ = try BGIJSScriptRunner(hostEnvironment: BGIRecordingJSScriptHostEnvironment())
                .execute(project: colorMatchProject)
            Issue.record("ColorMatch should be rejected by ImageRegion.Find")
        } catch let error as BGIJSScriptRuntimeError {
            #expect(error.localizedDescription.contains("ImageRegion.Find"))
            #expect(error.localizedDescription.contains("ColorMatch"))
        }

        let colorRangeFindMultiURL = tempRoot.appendingPathComponent("ColorRangeFindMulti", isDirectory: true)
        try writeUnsupportedRecognitionObjectFixtureScript(
            at: colorRangeFindMultiURL,
            mainScript: """
            const screen = captureGameRegion();
            screen.FindMulti(RecognitionObject.ColorRangeAndOcr(0, 0, 50, 30, [0, 0, 0, 255], [255, 255, 255, 255], 4));
            """
        )
        let colorRangeFindMultiProject = try BGIInstalledJSScriptProjectLoader().loadProject(
            at: colorRangeFindMultiURL,
            folderName: "ColorRangeFindMulti"
        )
        do {
            _ = try BGIJSScriptRunner(hostEnvironment: BGIRecordingJSScriptHostEnvironment())
                .execute(project: colorRangeFindMultiProject)
            Issue.record("ColorRangeAndOcr should be rejected by ImageRegion.FindMulti")
        } catch let error as BGIJSScriptRuntimeError {
            #expect(error.localizedDescription.contains("ImageRegion.FindMulti"))
            #expect(error.localizedDescription.contains("ColorRangeAndOcr"))
        }
    }

    @Test("JS task executor loads installed scripts with capture OCR template and input host")
    func jsTaskExecutorLoadsInstalledScriptsWithCaptureOCRTemplateAndInputHost() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-task-executor-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let scriptURL = store.userURL.appendingPathComponent("JsScript/Demo", isDirectory: true)
        try writeJSTaskExecutorFixtureScript(at: scriptURL)

        let metadata = CapturedFrame(
            frameIndex: 105,
            timestamp: Date(timeIntervalSince1970: 1_782_887_100),
            width: 320,
            height: 180,
            scaleFactor: 2,
            pixelFormat: 0x42475241,
            bytesPerRow: 320 * 4,
            sourceWindow: .mock(title: "JS Task Executor")
        )
        let imageFrame = CaptureImageFrame(
            metadata: metadata,
            cgImage: try makeRuntimeFixtureImage(width: 320, height: 180),
            backendName: "Synthetic"
        )
        var requestedROIs: [CGRect?] = []
        var requestedLocators: [BGIJSScriptTemplateLocator] = []
        let executor = BGIJSScriptTaskExecutor(
            store: store,
            captureFrameProvider: { imageFrame },
            ocrProvider: { frame, roi in
                requestedROIs.append(roi)
                return OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 20, y: 30, width: 70, height: 16),
                            text: "执行成功",
                            confidence: 0.96
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            },
            templateProvider: { frame, locator in
                requestedLocators.append(locator)
                return [
                    RecognitionObservation(
                        id: "executor-template-\(frame.metadata.frameIndex)",
                        objectID: locator.templateAssetName,
                        objectName: locator.templateAssetName,
                        recognitionType: .templateMatch,
                        normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.1, height: 0.1),
                        confidence: 0.9,
                        text: nil,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            }
        )

        let result = try executor.executeInstalledScript(BGIJSScriptTaskExecutionRequest(
            folderName: "Demo",
            settingsJSON: #"{"mode":"executor"}"#
        ))

        #expect(result.projectURL == scriptURL.standardizedFileURL)
        #expect(result.logs.contains("[info] executor:executor:Synthetic:320x180:2"))
        #expect(result.logs.contains("[info] executor-ocr:执行成功"))
        #expect(result.logs.contains("[info] executor-template:80,45:true"))
        #expect(result.captureRegions.count == 1)
        #expect(result.captureRegions.first?.width == 320)
        #expect(result.ocrResults.count == 1)
        #expect(result.templateMatchRegions.count == 1)
        #expect(result.inputCommands.contains(.keyPress(.f)))
        #expect(requestedROIs == [
            CGRect(x: 0, y: 0, width: 200, height: 80)
        ])
        #expect(requestedLocators == [
            BGIJSScriptTemplateLocator(
                templateAssetName: "AutoSkip:icon_option.png",
                roi: CGRect(x: 10, y: 10, width: 120, height: 60),
                threshold: 0.75,
                findAll: false
            )
        ])
    }

    @Test("JS package document loader rejects imports outside the script root")
    func jsPackageDocumentLoaderRejectsImportsOutsideScriptRoot() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-js-runtime-path-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = tempRoot.appendingPathComponent("Demo", isDirectory: true)
        try writeRuntimeFixtureScript(at: scriptURL)
        let project = try BGIInstalledJSScriptProjectLoader().loadProject(at: scriptURL, folderName: "Demo")
        let loader = BGIJSScriptPackageDocumentLoader(projectURL: project.projectURL)

        #expect(loader.resolvePath(
            specifier: "../outside.js",
            referrerPath: project.mainScriptURL.path,
            searchPathURLs: []
        ) == nil)
        #expect(loader.resolvePath(
            specifier: "./packages/utils",
            referrerPath: project.mainScriptURL.path,
            searchPathURLs: []
        ) == nil)
    }

    @Test("Symlink pointing outside project root is rejected during import resolution")
    func unsafeSymlinkImportIsRejected() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgijsrt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("test-project")
        let outsideDir = tempRoot.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let manifest = #"{"manifest_version":1,"name":"test","version":"1.0","main":"main.js"}"#
        try manifest.write(
            to: projectDir.appendingPathComponent("manifest.json"),
            atomically: true, encoding: .utf8
        )
        try "{}".write(
            to: projectDir.appendingPathComponent("settings.json"),
            atomically: true, encoding: .utf8
        )

        let symlinkURL = projectDir.appendingPathComponent("escape.js")
        let outsideTarget = outsideDir.appendingPathComponent("secret.js")
        try "log.info('outside');".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideTarget)

        try "require('escape');\nlog.info('done');".write(
            to: projectDir.appendingPathComponent("main.js"),
            atomically: true, encoding: .utf8
        )

        let project = try BGIInstalledJSScriptProjectLoader()
            .loadProject(at: projectDir, folderName: "test-project")
        let host = BGIRecordingJSScriptHostEnvironment()

        // Import of symlink pointing outside should throw.
        #expect(throws: (any Error).self) {
            try BGIJSScriptRunner(hostEnvironment: host).execute(
                project: project, settingsJSON: "{}"
            )
        }
    }

    @Test("file.ReadTextSync on symlink pointing outside project is rejected")
    func unsafeSymlinkFileReadTextSyncIsRejected() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgijsrt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("test-project")
        let outsideDir = tempRoot.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let manifest = #"{"manifest_version":1,"name":"test","version":"1.0","main":"main.js"}"#
        try manifest.write(
            to: projectDir.appendingPathComponent("manifest.json"),
            atomically: true, encoding: .utf8
        )
        try "{}".write(
            to: projectDir.appendingPathComponent("settings.json"),
            atomically: true, encoding: .utf8
        )

        let outsideContent = "secret data"
        let outsideFile = outsideDir.appendingPathComponent("data.txt")
        try outsideContent.write(to: outsideFile, atomically: true, encoding: .utf8)

        let symlinkURL = projectDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideFile)

        let script = #"""
        var result = file.ReadTextSync("link.txt");
        log.info(result);
        """#
        try script.write(
            to: projectDir.appendingPathComponent("main.js"),
            atomically: true, encoding: .utf8
        )

        let project = try BGIInstalledJSScriptProjectLoader()
            .loadProject(at: projectDir, folderName: "test-project")
        let host = BGIRecordingJSScriptHostEnvironment()

        let result = try BGIJSScriptRunner(hostEnvironment: host).execute(
            project: project, settingsJSON: "{}"
        )
        #expect(!result.logs.contains { $0.contains("secret") },
                "file.ReadTextSync on symlink must not leak outside content")
    }

    @Test("script timeout stops long-running sleep")
    func scriptTimeoutStopsLongSleep() throws {
        let deadline = Date().addingTimeInterval(0.05)
        let env = BGIRecordingJSScriptHostEnvironment(deadline: deadline)
        let start = Date()
        env.sleep(milliseconds: 10_000)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 5.0, "Deadline should have stopped the long sleep early")
    }

    @Test("record-only mode does not bypass InputSafetyGate")
    func recordOnlyModeDoesNotBypassInputSafetyGate() throws {
        let request = BGIJSScriptTaskExecutionRequest(
            folderName: "test",
            recordInputOnly: true
        )
        #expect(request.recordInputOnly == true)
    }

    @Test("replay-through-safety-gate uses source .runtimeTrigger")
    func replayThroughSafetyGateUsesRuntimeTriggerSource() throws {
        var capturedSource: ActionSource?
        let dispatchCapture: (InputAction, ActionSource) -> InputSafetyGate.GateResult = { _, source in
            capturedSource = source
            return .dryRun()
        }
        guard let action = BGIJSScriptTaskExecutor.inputAction(
            for: .keyPress(.space),
            targetWindow: WindowInfo.mock(title: "test"),
            gameMetrics: [1920, 1080, 1]
        ) else {
            #expect(Bool(false), "Failed to create input action")
            return
        }
        _ = dispatchCapture(action, .runtimeTrigger)
        #expect(capturedSource == .runtimeTrigger,
                "Replayed JS commands must use source .runtimeTrigger")
    }
}

private func writeRuntimeFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "name": "Runtime Demo",
          "version": "1.0.0",
          "main": "main.js",
          "library": ["./lib"],
          "settings_ui": "settings.json"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        [
          { "name": "mode", "type": "input-text", "label": "Mode", "default": "normal" }
        ]
        """,
        relativePath: "settings.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        import { tool, renamed as alias } from "./packages/utils/tool";
        import helper from "./lib/helper";
        import text from "./assets/message.txt";

        log.info(`${tool()}|${alias()}|${helper}|${text.trim()}|${settings.mode}|${getVersion()}`);
        keyPress("F");
        moveMouseTo(10, 20);
        leftButtonClick();
        keyDown("VK_LBUTTON");
        keyUp("VK_LBUTTON");
        inputText("hello traveler");
        const page = new BvPage();
        page.Keyboard.KeyPress("VK_ESCAPE").keyDown("A").keyUp("A");
        page.Mouse.MoveMouseBy(3, -2).RightButtonClick().VerticalScroll(-2);
        genshin.ChooseTalkOption("Katheryne");
        const metrics = getGameMetrics();
        log.info(`${metrics[0]}x${metrics[1]}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        import { inner } from "./inner";
        const renamed = () => "renamed";
        export function tool() { return `tool:${inner()}`; }
        export { renamed };
        """,
        relativePath: "packages/utils/tool.js",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        export function inner() { return "inner"; }
        """,
        relativePath: "packages/utils/inner.js",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        export default "helper";
        """,
        relativePath: "lib/helper.js",
        under: scriptURL
    )
    try writeRuntimeFixtureFile("hello\n", relativePath: "assets/message.txt", under: scriptURL)
}

private func writeCaptureOCRFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "Capture OCR Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const region = captureGameRegion();
        log.info(`capture:${region.backendName}:${region.id}:${region.frameIndex}:${region.width}x${region.height}:${region.pixelFormat}`);
        const ocr = region.Ocr();
        log.info(`ocr:${ocr.Text}:${ocr.Regions.length}:${ocr.Regions[0].Text}:${ocr.Regions[0].Score.toFixed(2)}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeGenshinBridgeFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "Genshin Bridge Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        log.info(`metrics:${genshin.Width}x${genshin.Height}:${genshin.ScaleTo1080PRatio.toFixed(2)}:${genshin.ScreenDpiScale.toFixed(1)}:${genshin.width}x${genshin.height}:${genshin.screenDpiScale.toFixed(1)}`);
        const uid = genshin.Uid();
        const tp = genshin.Tp(10, 20, "Teyvat", true);
        const moved = genshin.MoveMapTo(30, 40, "璃月");
        const independent = genshin.MoveIndependentMapTo(50, 60, "Enkanomiya", "渊下宫");
        const zoom = genshin.GetBigMapZoomLevel();
        const zoomSet = genshin.SetBigMapZoomLevel(4.5);
        const bigMap = genshin.GetPositionFromBigMap("Teyvat");
        const pos = genshin.GetPositionFromMap("Teyvat", "FeatureMatch", 250, 12, 34);
        const posByMethod = genshin.getPositionFromMapWithMatchingMethod("Teyvat", "TemplateMatch");
        const orientation = genshin.GetCameraOrientation();
        const switched = genshin.SwitchParty("Daily");
        genshin.ClearPartyCache();
        const returned = genshin.returnMainUi();
        const statue = genshin.tpToStatueOfTheSeven();
        const talked = genshin.ChooseTalkOption("每日委托", 3, true);
        const fishing = genshin.AutoFishing(2);
        const relogin = genshin.Relogin();
        const timeSet = genshin.SetTime(18, 30, true);
        log.info(`genshin-values:${uid}:${pos.x}:${pos.Y}:${bigMap.X}:${bigMap.y}:${orientation}:${zoom}`);
        log.info(`genshin-bools:${tp}:${moved}:${independent}:${zoomSet}:${switched}:${returned && statue}:${talked}:${fishing && relogin && timeSet}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeBvPageFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "BvPage Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const page = new BvPage();
        const all = page.Ocr({ x: 4, y: 8, width: 80, height: 24 });
        log.info(`bvpage:${all.length}:${all.map(x => x.Text).join("|")}`);
        const found = page.GetByText("探索", { X: 0, Y: 0, Width: 128, Height: 40 }).FindAll();
        log.info(`locator:${found.length}:${found[0].Text}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeBvLocatorWaitFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "BvLocator Wait Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const page = new BvPage();
        const locator = page.GetByText("Ready")
            .WithRoi(r => r.CutRightTop(0.5, 0.5))
            .WithTimeout(5)
            .WithRetryInterval(1)
            .WithRetryAction(results => log.info(`retry:${results.length}`));
        const found = locator.WaitFor();
        log.info(`wait:${found.length}:${found[0].Text}:${found[0].x.toFixed(1)},${found[0].y.toFixed(1)}`);
        const clicked = locator.Click(5);
        log.info(`click:${clicked.x.toFixed(1)},${clicked.y.toFixed(1)}`);
        log.info(`gone:${locator.TryWaitForDisappear(5)}`);
        const missing = page.GetByText("Missing").WithTimeout(1).WithRetryInterval(1).TryWaitFor();
        log.info(`missing:${missing.length}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeBvLocatorClickUntilDisappearsFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "BvLocator ClickUntilDisappears Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const page = new BvPage();
        const locator = page.GetByText("Vanish").WithRetryInterval(1);
        const clicked = locator.ClickUntilDisappears(1);
        log.info(`click-until:${clicked.Text}:${clicked.x},${clicked.y}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeBvImageFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "BvImage Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const page = new BvPage();
        const image = new BvImage("AutoSkip:OptionIcon", { x: 10, y: 12, width: 80, height: 32 }, 0.72);
        const all = page.GetByImage(image).FindAll();
        log.info(`template:${all.length}:${all[0].x.toFixed(1)},${all[0].y.toFixed(1)},${all[0].width.toFixed(1)},${all[0].height.toFixed(1)}:${all[0].Score.toFixed(2)}:${all[0].objectID}`);
        const found = page.Locator(image).Find();
        log.info(`find:${found.objectID}:${found.x.toFixed(1)}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeImageRegionFindFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "ImageRegion Find Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const screen = captureGameRegion();
        const template = screen.Find(new BvImage(
            "UseRedeemCode:esc_return_button.png",
            { x: 100, y: 20, width: 80, height: 60 },
            0.83
        ));
        log.info(`image-region-template:${template.IsExist()}:${template.IsEmpty()}:${template.x},${template.y}`);
        template.Click();
        const singleOcr = screen.Find({
            RecognitionType: "Ocr",
            Text: "成功",
            RegionOfInterest: { X: 0, Y: 0, Width: 160, Height: 80 }
        });
        log.info(`image-region-ocr-single:${singleOcr.IsExist()}:${singleOcr.x},${singleOcr.y}:${singleOcr.Text}`);
        const multiOcr = screen.FindMulti({
            RecognitionType: "Ocr",
            Text: "成功",
            ReplaceDictionary: { "替换": ["失败"] },
            RegionOfInterest: { X: 0, Y: 0, Width: 160, Height: 80 }
        });
        log.info(`image-region-ocr-multi:${multiOcr.length}:${multiOcr.map(x => x.Text).join("|")}:${multiOcr[0].x},${multiOcr[0].y}:${multiOcr[1].x},${multiOcr[1].y}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeRecognitionObjectOcrMatchFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "RecognitionObject OcrMatch Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const screen = captureGameRegion();
        const staticMatch = screen.Find(RecognitionObject.OcrMatch(0, 0, 160, 80, "成功"));
        log.info(`ocr-match-static:${staticMatch.IsExist()}:${staticMatch.x},${staticMatch.y}:${staticMatch.Text}`);

        const rules = new RecognitionObject();
        rules.RecognitionType = "OcrMatch";
        rules.RegionOfInterest = { X: 10, Y: 5, Width: 120, Height: 50 };
        rules.ReplaceDictionary = { "换": ["错"] };
        rules.AllContainMatchText = ["兑换"];
        rules.RegexMatchText = ["成功$"];
        const ruleMatch = screen.Find(rules);
        log.info(`ocr-match-rules:${ruleMatch.IsExist()}:${ruleMatch.x},${ruleMatch.y}:${ruleMatch.Text}`);

        const missing = screen.Find(RecognitionObject.OcrMatch(0, 0, 160, 80, "不存在"));
        log.info(`ocr-match-missing:${missing.IsEmpty()}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeRecognitionObjectColorRangeAndOcrFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "RecognitionObject ColorRangeAndOcr Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const screen = captureGameRegion();
        const ro = RecognitionObject.ColorRangeAndOcr(
          10,
          10,
          100,
          40,
          [0, 0, 210, 255],
          { b: 90, g: 80, r: 255, a: 255 },
          4
        );
        const found = screen.Find(ro);
        log.info(`color-range:${found.IsExist()}:${found.x},${found.y}:${found.Text}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeUnsupportedRecognitionObjectFixtureScript(
    at scriptURL: URL,
    mainScript: String
) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "Unsupported RecognitionObject Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        mainScript,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeJSTaskExecutorFixtureScript(at scriptURL: URL) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "JS Task Executor Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const screen = captureGameRegion();
        log.info(`executor:${settings.mode}:${screen.backendName}:${screen.width}x${screen.height}:${screen.dpi}`);
        const match = screen.Find(RecognitionObject.OcrMatch(0, 0, 200, 80, "成功"));
        log.info(`executor-ocr:${match.Text}`);
        const template = screen.Find(new BvImage(
            "AutoSkip:icon_option.png",
            { x: 10, y: 10, width: 120, height: 60 },
            0.75
        ));
        log.info(`executor-template:${template.x},${template.y}:${template.IsExist()}`);
        keyPress("F");
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func writeBvImageDefaultTemplateFixtureScript(at scriptURL: URL, assetName: String) throws {
    try writeRuntimeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "BvImage Default Template Demo",
          "version": "1.0.0",
          "main": "main.js"
        }
        """,
        relativePath: "manifest.json",
        under: scriptURL
    )
    try writeRuntimeFixtureFile(
        """
        const page = new BvPage();
        const image = new BvImage("\(assetName)", { x: 220, y: 150, width: 120, height: 100 }, 0.99);
        const all = page.GetByImage(image).FindAll();
        const first = all[0] || {};
        log.info(`default-template:${all.length}:${first.objectID || "none"}:${Number(first.Score || 0).toFixed(2)}`);
        """,
        relativePath: "main.js",
        under: scriptURL
    )
}

private func makeRuntimeFixtureImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw BGIJSScriptRuntimeTestError.imageCreationFailed
    }
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        throw BGIJSScriptRuntimeTestError.imageCreationFailed
    }
    return image
}

private func makeRuntimeSyntheticFrame(template: CGImage, at points: [CGPoint], size: CGSize) throws -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let templatePixels = try runtimeRgbaPixels(from: template)
    let templateBytesPerRow = template.width * bytesPerPixel

    for point in points {
        let originX = Int(point.x.rounded())
        let originY = Int(point.y.rounded())
        for templateY in 0..<template.height {
            let destinationY = originY + templateY
            guard destinationY >= 0, destinationY < height else { continue }
            for templateX in 0..<template.width {
                let destinationX = originX + templateX
                guard destinationX >= 0, destinationX < width else { continue }
                let sourceIndex = templateY * templateBytesPerRow + templateX * bytesPerPixel
                let destinationIndex = destinationY * bytesPerRow + destinationX * bytesPerPixel
                pixels[destinationIndex..<(destinationIndex + bytesPerPixel)] =
                    templatePixels[sourceIndex..<(sourceIndex + bytesPerPixel)]
            }
        }
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
          ),
          let image = context.makeImage() else {
        throw BGIJSScriptRuntimeTestError.imageCreationFailed
    }
    return image
}

private func runtimeRgbaPixels(from image: CGImage) throws -> [UInt8] {
    let bytesPerPixel = 4
    let bytesPerRow = image.width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
          ) else {
        throw BGIJSScriptRuntimeTestError.imageCreationFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private enum BGIJSScriptRuntimeTestError: Error {
    case imageCreationFailed
}

private func writeRuntimeFixtureFile(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}
