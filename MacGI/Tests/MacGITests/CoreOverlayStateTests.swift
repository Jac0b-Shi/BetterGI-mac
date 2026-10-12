import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("Core overlay state")
struct CoreOverlayStateTests {
    @Test("Set remove and clear preserve named overlay semantics")
    func stateTransitions() throws {
        var state = CoreOverlayState()
        try state.apply(parameters: [
            "name": "fixture", "operation": "setLabels",
            "rectangles": [["x": 10, "y": 20, "width": 30, "height": 40,
                            "text": "target", "recognized": true]]
        ])
        try state.apply(parameters: [
            "name": "SkillCdText", "operation": "setText",
            "commands": [["Text": "4.2", "X": 100, "Y": 200]]
        ])
        #expect(state.allLabels.count == 1)
        #expect(state.allLabels.first?.rect == CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(state.allTexts.first?.text == "4.2")

        try state.apply(parameters: ["name": "fixture", "operation": "removeLabels"])
        #expect(state.allLabels.isEmpty)
        try state.apply(parameters: ["name": "", "operation": "clearAll"])
        #expect(state.allTexts.isEmpty)
    }

    @Test("Drawing snapshots replace groups and reject malformed updates atomically")
    func drawingSnapshots() throws {
        var state = CoreOverlayState()
        try state.apply(parameters: [
            "name": "MaskWindowDrawing", "operation": "setDrawingSnapshot", "version": 1,
            "groups": [["name": "cooldown", "kind": "Feature", "shapes": [
                ["type": "line", "x": 10, "y": 20, "x2": 30, "y2": 40, "color": "#FFFF0000"],
                ["type": "text", "x": 10, "y": 20, "text": "4.2", "numeric": true]
            ]]]
        ])
        #expect(state.drawingShapes.count == 2)
        #expect(state.drawingShapes.allSatisfy { $0.isFeature })
        #expect(state.drawingShapes.first?.end == CGPoint(x: 30, y: 40))
        let previous = state
        do {
            try state.apply(parameters: [
                "name": "MaskWindowDrawing", "operation": "setDrawingSnapshot", "version": 2,
                "groups": [["name": "invalid", "kind": "invalid", "shapes": []]]
            ])
            Issue.record("Malformed drawing snapshot was accepted")
        } catch {
            #expect(state == previous)
        }
        try state.apply(parameters: [
            "name": "MaskWindowDrawing", "operation": "setDrawingSnapshot", "version": 3, "groups": []
        ])
        #expect(state.drawingShapes.isEmpty)
        #expect(state.drawingVersion == 3)
    }

    @Test("Map viewport updates independently from point data")
    func mapViewportUpdatesIndependently() throws {
        var state = CoreOverlayState()
        try state.apply(parameters: [
            "name": "MapMask", "operation": "setMapViewport",
            "isInBigMapUi": true,
            "bigMapViewport": ["x": 100, "y": 200, "width": 800, "height": 450]
        ])
        #expect(state.isInBigMapUI)
        #expect(state.bigMapViewport == CGRect(x: 100, y: 200, width: 800, height: 450))
        #expect(state.mapPoints.isEmpty)

        try state.apply(parameters: [
            "name": "MapMask", "operation": "setMapViewport",
            "isInBigMapUi": false,
            "bigMapViewport": NSNull(),
            "miniMapViewport": NSNull()
        ])
        #expect(!state.isInBigMapUI)
        #expect(state.bigMapViewport == nil)
        #expect(state.miniMapViewport == nil)
    }

    @Test("MapMask keeps Core map coordinates separate from viewport")
    func rawMapPoints() throws {
        var state = CoreOverlayState()
        try state.apply(parameters: [
            "name": "MapMask",
            "operation": "setMapPointData",
            "isLoading": false,
            "points": [[
                "Id": "42",
                "Label": "矿物",
                "IconUrl": "https://example.invalid/icon.png",
                "ImageX": 1250,
                "ImageY": 875,
                "IsHidden": true
            ]]
        ])

        #expect(!state.isMapMaskLoading)
        #expect(state.mapPoints.first?.sourceID == "42")
        #expect(state.mapPoints.first?.imagePosition == CGPoint(x: 1250, y: 875))
        #expect(state.mapPoints.first?.isHidden == true)
    }
}
