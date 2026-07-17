import CoreGraphics
import Foundation

/// Scene-level (region-wide) coordinate system converter.
///
/// Ports `SceneBaseMap` from upstream BetterGI. The scene map uses a different
/// coordinate space than the per-layer tile maps used by `BGIMiniMapTemplateLayer`.
/// This converter handles the genshin-map ↔ image-coordinate mapping that the
/// big-map UI and teleport system rely on.
///
/// Upstream reference:
///   `SceneBaseMap.ConvertGenshinMapCoordinatesToImageCoordinates`
///   `SceneBaseMap.ConvertImageCoordinatesToGenshinMapCoordinates`
struct BGISceneMapCoordinateConverter: Sendable {

    /// The map origin position in the full-resolution image, in pixels.
    let mapOriginInImage: CGPoint

    /// Scale from genshin (1024‑based) coordinates to image pixels.
    /// Equal to `mapImageBlockWidth / 1024`.
    let imageBlockWidthScale: Double

    /// Total image size for the full region map, in pixels.
    let imageSize: CGSize

    // MARK: - Conversion

    /// Convert genshin map coordinates → image pixel coordinates.
    /// Returns the matched image point, or `nil` if the input is zero.
    func genshinToImage(_ genshinPoint: CGPoint?) -> CGPoint? {
        guard let p = genshinPoint, !(p.x == 0 && p.y == 0) else { return nil }
        return CGPoint(
            x: mapOriginInImage.x - p.x * imageBlockWidthScale,
            y: mapOriginInImage.y - p.y * imageBlockWidthScale
        )
    }

    /// Convert image pixel coordinates → genshin map coordinates.
    /// Returns `nil` if the input is zero.
    func imageToGenshin(_ imagePoint: CGPoint) -> CGPoint? {
        guard !(imagePoint.x == 0 && imagePoint.y == 0) else { return nil }
        return CGPoint(
            x: (mapOriginInImage.x - imagePoint.x) / imageBlockWidthScale,
            y: (mapOriginInImage.y - imagePoint.y) / imageBlockWidthScale
        )
    }

    // MARK: - Factories

    /// Teyvat continent converter.
    ///
    /// Upstream constants from `TeyvatMap`:
    ///   - `GameMapCols = 22`, `GameMapRows = 15`
    ///   - `GameMapLeftCols = 15`, `GameMapUpRows = 7`
    ///   - `MapImageBlockWidth = 2048`
    ///   → `MapOriginInImageCoordinate = ((15+1)*2048, (7+1)*2048) = (32768, 16384)`
    ///   → `ImageBlockWidthScale = 2048 / 1024 = 2.0`
    static let teyvat = BGISceneMapCoordinateConverter(
        mapOriginInImage: CGPoint(x: 32768, y: 16384),
        imageBlockWidthScale: 2.0,
        imageSize: CGSize(width: 22 * 2048, height: 15 * 2048) // 45056 × 30720
    )

    /// Create a converter for a specific region.
    /// Placeholder — other regions need their own constants.
    static func forRegion(_ region: String) -> BGISceneMapCoordinateConverter {
        switch region.lowercased() {
        case "teyvat": return .teyvat
        default:
            // Fallback to Teyvat parameters; other maps may need adjustments.
            return .teyvat
        }
    }
}
