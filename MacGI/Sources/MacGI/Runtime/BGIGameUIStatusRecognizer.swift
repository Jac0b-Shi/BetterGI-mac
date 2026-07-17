import CoreGraphics
import Foundation

struct BGIGameUIStatusRecognitionResult: Equatable, Sendable {
    var observations: [RecognitionObservation]
    var isInMainUI: Bool
    var isInBigMapUI: Bool
    var isBigMapUnderground: Bool
    var bigMapScaleFraction: Double?
    var report: TemplateRecognitionReport

    var mapScaleObservation: RecognitionObservation? {
        observations.first { $0.objectID == BGIGameUIStatusRecognizer.mapScaleObjectID }
    }

    var mapSettingsObservation: RecognitionObservation? {
        observations.first { $0.objectID == BGIGameUIStatusRecognizer.mapSettingsObjectID }
    }

    var mapUndergroundObservation: RecognitionObservation? {
        observations.first { $0.objectID == BGIGameUIStatusRecognizer.mapUndergroundObjectID }
    }

    var paimonMenuObservation: RecognitionObservation? {
        observations.first { $0.objectID == BGIGameUIStatusRecognizer.paimonMenuObjectID }
    }
}

/// First-layer macOS port of upstream `BvStatus` UI checks.
///
/// Upstream `Bv.IsInBigMapUi` returns true when either the QuickTeleport map
/// scale button or map settings button is visible. `Bv.GetBigMapScale` then
/// derives the zoom fraction from the scale-button center Y in 1080p space.
/// Upstream `Bv.IsInMainUi` starts from the Paimon menu template; task ports
/// that own OCR providers can layer the revive-prompt exclusion on top.
struct BGIGameUIStatusRecognizer {
    static let mapScaleObjectID = "QuickTeleport.MapScaleButtonRo"
    static let mapSettingsObjectID = "QuickTeleport.MapSettingsButtonRo"
    static let mapUndergroundObjectID = "QuickTeleport.MapUndergroundSwitchButtonRo"
    static let paimonMenuObjectID = "Common.Element.PaimonMenuRo"

    private let templateEngine: TemplateMatchingRecognitionEngine
    private let zoomStartY: Double
    private let zoomEndY: Double

    init(
        templateEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        zoomStartY: Double = 468,
        zoomEndY: Double = 612
    ) {
        self.templateEngine = templateEngine
        self.zoomStartY = zoomStartY
        self.zoomEndY = zoomEndY
    }

    func recognize(_ frame: CaptureImageFrame) -> BGIGameUIStatusRecognitionResult {
        let report = templateEngine.recognize(
            imageFrame: frame,
            objects: RecognitionObject.bgiQuickTeleportBigMapStatusObjects
                + RecognitionObject.bgiCommonElementMainUIObjects
        )
        let observations = report.observations
        let hasScale = observations.contains { $0.objectID == Self.mapScaleObjectID }
        let hasSettings = observations.contains { $0.objectID == Self.mapSettingsObjectID }
        let isUnderground = observations.contains { $0.objectID == Self.mapUndergroundObjectID }
        let hasPaimonMenu = observations.contains { $0.objectID == Self.paimonMenuObjectID }
        let scale = observations
            .first { $0.objectID == Self.mapScaleObjectID }
            .flatMap(bigMapScaleFraction)

        return BGIGameUIStatusRecognitionResult(
            observations: observations,
            isInMainUI: hasPaimonMenu,
            isInBigMapUI: hasScale || hasSettings,
            isBigMapUnderground: isUnderground,
            bigMapScaleFraction: scale,
            report: report
        )
    }

    func bigMapScaleFraction(from observation: RecognitionObservation) -> Double? {
        guard zoomEndY != zoomStartY else { return nil }
        let centerY1080 = observation.normalizedRect.midY * 1080.0
        return (zoomEndY - centerY1080) / (zoomEndY - zoomStartY)
    }
}
