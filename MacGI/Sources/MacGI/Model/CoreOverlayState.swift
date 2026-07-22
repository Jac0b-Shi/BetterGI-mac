import CoreGraphics
import Combine
import Foundation

struct CoreOverlayRectangle: Identifiable, Equatable {
    let id: String
    let name: String
    let rect: CGRect
}

struct CoreOverlayLabel: Identifiable, Equatable {
    let id: String
    let name: String
    let rect: CGRect
    let text: String
    let recognized: Bool
}

struct CoreOverlayText: Identifiable, Equatable {
    let id: String
    let name: String
    let text: String
    let position: CGPoint
}

struct CoreOverlayMapPoint: Identifiable, Equatable {
    let id: String
    let sourceID: String
    let label: String
    let iconURL: URL?
    let imagePosition: CGPoint
    let isHidden: Bool
}

struct CoreOverlayState: Equatable {
    private(set) var rectangles: [String: [CoreOverlayRectangle]] = [:]
    private(set) var labels: [String: [CoreOverlayLabel]] = [:]
    private(set) var texts: [String: [CoreOverlayText]] = [:]
    private(set) var mapPoints: [CoreOverlayMapPoint] = []
    private(set) var bigMapViewport: CGRect?
    private(set) var miniMapViewport: CGRect?
    private(set) var isInBigMapUI = false
    private(set) var isMapMaskLoading = false

    var allRectangles: [CoreOverlayRectangle] { rectangles.keys.sorted().flatMap { rectangles[$0] ?? [] } }
    var allLabels: [CoreOverlayLabel] { labels.keys.sorted().flatMap { labels[$0] ?? [] } }
    var allTexts: [CoreOverlayText] { texts.keys.sorted().flatMap { texts[$0] ?? [] } }

    mutating func apply(parameters: [String: Any]) throws {
        guard let name = parameters["name"] as? String,
              let operation = parameters["operation"] as? String else {
            throw CoreOverlayCommandError.invalid("overlay.command requires name and operation.")
        }

        switch operation {
        case "setRectangles":
            rectangles[name] = try Self.parseRectangles(parameters["rectangles"], name: name)
        case "removeRectangles":
            rectangles.removeValue(forKey: name)
        case "setLabels":
            labels[name] = try Self.parseLabels(parameters["rectangles"], name: name)
        case "removeLabels":
            labels.removeValue(forKey: name)
        case "setText":
            texts[name] = try Self.parseTexts(parameters["commands"], name: name)
        case "removeText":
            texts.removeValue(forKey: name)
        case "clearAll":
            rectangles.removeAll()
            labels.removeAll()
            texts.removeAll()
            mapPoints.removeAll()
            bigMapViewport = nil
            miniMapViewport = nil
            isInBigMapUI = false
            isMapMaskLoading = false
        case "setMapPointData":
            guard name == "MapMask", let isLoading = parameters["isLoading"] as? Bool else {
                throw CoreOverlayCommandError.invalid(
                    "MapMask point-data command requires loading state.")
            }
            isMapMaskLoading = isLoading
            mapPoints = try Self.parseMapPoints(parameters["points"])
        case "setMapViewport":
            guard name == "MapMask" else {
                throw CoreOverlayCommandError.invalid("MapMask viewport has an invalid owner.")
            }
            if let value = parameters["isInBigMapUi"] as? Bool {
                isInBigMapUI = value
            }
            if parameters.keys.contains("bigMapViewport") {
                bigMapViewport = try Self.optionalRect(parameters["bigMapViewport"])
            }
            if parameters.keys.contains("miniMapViewport") {
                miniMapViewport = try Self.optionalRect(parameters["miniMapViewport"])
            }
        default:
            throw CoreOverlayCommandError.invalid("Unsupported overlay operation: \(operation)")
        }
    }

    private static func parseRectangles(_ value: Any?, name: String) throws -> [CoreOverlayRectangle] {
        try dictionaries(value, field: "rectangles").enumerated().map { index, item in
            CoreOverlayRectangle(id: "\(name)-rect-\(index)", name: name, rect: try rect(item))
        }
    }

    private static func parseLabels(_ value: Any?, name: String) throws -> [CoreOverlayLabel] {
        try dictionaries(value, field: "rectangles").enumerated().map { index, item in
            guard let text = item["text"] as? String, let recognized = item["recognized"] as? Bool else {
                throw CoreOverlayCommandError.invalid("Overlay label requires text and recognized.")
            }
            return CoreOverlayLabel(
                id: "\(name)-label-\(index)", name: name, rect: try rect(item),
                text: text, recognized: recognized)
        }
    }

    private static func parseTexts(_ value: Any?, name: String) throws -> [CoreOverlayText] {
        try dictionaries(value, field: "commands").enumerated().map { index, item in
            guard let text = (item["Text"] ?? item["text"]) as? String,
                  let x = number(item["X"] ?? item["x"]),
                  let y = number(item["Y"] ?? item["y"]) else {
                throw CoreOverlayCommandError.invalid("Overlay text requires Text, X and Y.")
            }
            return CoreOverlayText(
                id: "\(name)-text-\(index)", name: name, text: text,
                position: CGPoint(x: x, y: y))
        }
    }

    private static func parseMapPoints(_ value: Any?) throws -> [CoreOverlayMapPoint] {
        try dictionaries(value, field: "points").map { item in
            guard let sourceID = (item["Id"] ?? item["id"]) as? String,
                  let label = (item["Label"] ?? item["label"]) as? String,
                  let imageX = number(item["ImageX"] ?? item["imageX"]),
                  let imageY = number(item["ImageY"] ?? item["imageY"]),
                  let isHidden = (item["IsHidden"] ?? item["isHidden"]) as? Bool else {
                throw CoreOverlayCommandError.invalid("MapMask point contains invalid fields.")
            }
            let iconText = (item["IconUrl"] ?? item["iconUrl"]) as? String
            return CoreOverlayMapPoint(
                id: "map-mask-\(sourceID)",
                sourceID: sourceID,
                label: label,
                iconURL: iconText.flatMap(URL.init(string:)),
                imagePosition: CGPoint(x: imageX, y: imageY),
                isHidden: isHidden)
        }
    }

    private static func optionalRect(_ value: Any?) throws -> CGRect? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let item = value as? [String: Any] else {
            throw CoreOverlayCommandError.invalid("MapMask viewport must be an object or null.")
        }
        let result = try rect(item)
        return result.width > 0 && result.height > 0 ? result : nil
    }

    private static func dictionaries(_ value: Any?, field: String) throws -> [[String: Any]] {
        guard let values = value as? [[String: Any]] else {
            throw CoreOverlayCommandError.invalid("overlay.command requires an array in \(field).")
        }
        return values
    }

    private static func rect(_ item: [String: Any]) throws -> CGRect {
        guard let x = number(item["x"]), let y = number(item["y"]),
              let width = number(item["width"]), let height = number(item["height"]),
              width >= 0, height >= 0 else {
            throw CoreOverlayCommandError.invalid("Overlay rectangle contains invalid geometry.")
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func number(_ value: Any?) -> CGFloat? {
        guard let value = value as? NSNumber else { return nil }
        let result = CGFloat(value.doubleValue)
        return result.isFinite ? result : nil
    }
}

enum CoreOverlayCommandError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

@MainActor
final class CoreOverlayStore: ObservableObject {
    @Published private(set) var state = CoreOverlayState()

    func apply(parameters: [String: Any]) throws {
        var next = state
        try next.apply(parameters: parameters)
        state = next
    }
}
