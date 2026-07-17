import CoreGraphics
import Foundation

struct BGIMiniMapPreprocessStatistics: Equatable, Sendable {
    let iconMaskedPixels: Int
    let circlePixels: Int
    let usablePixels: Int

    var iconMaskRatio: Double {
        guard circlePixels > 0 else { return 0 }
        return Double(iconMaskedPixels) / Double(circlePixels)
    }

    var summary: String {
        "iconMasked=\(iconMaskedPixels) circle=\(circlePixels) usable=\(usablePixels) ratio=\(String(format: "%.3f", iconMaskRatio))"
    }
}

struct BGIMiniMapPreprocessResult: Sendable {
    let sourceImage: CGImage
    let iconMaskImage: CGImage
    let usableMaskImage: CGImage
    let iconMask: [UInt8]
    let usableMask: [UInt8]
    let statistics: BGIMiniMapPreprocessStatistics
}

struct BGIMiniMapMatchInputStatistics: Equatable, Sendable {
    let finalMaskPixels: Int
    let backgroundSeedPixels: Int
    let backgroundExpandedPixels: Int

    var summary: String {
        "finalMask=\(finalMaskPixels) bgSeed=\(backgroundSeedPixels) bgExpanded=\(backgroundExpandedPixels)"
    }
}

struct BGIMiniMapMatchInput: Sendable {
    let processedImage: CGImage
    let finalMaskImage: CGImage
    let backgroundMaskImage: CGImage
    let finalMask: [UInt8]
    let backgroundMask: [UInt8]
    let statistics: BGIMiniMapMatchInputStatistics
}

struct BGIMiniMapOrientationEstimate: Equatable, Sendable {
    let degrees: Double
    let confidence: Double

    var summary: String {
        "degrees=\(String(format: "%.2f", degrees)) confidence=\(String(format: "%.3f", confidence))"
    }
}

/// Swift port of the first stage of BetterGI `MiniMapPreprocessor`.
///
/// This mirrors `MaskCalculator.Process1` / `CreateIconMask`: consume the
/// BetterGI-compatible 156x156 mini map and identify high-confidence UI icon
/// pixels that must be masked before map matching.  `Process2` still needs the
/// upstream camera-orientation angle; keep this stage separate so the future
/// Rust/OpenCV path can replace or verify it directly.
struct BGIMiniMapPreprocessor: Sendable {
    func preprocess(_ image: CGImage) throws -> BGIMiniMapPreprocessResult {
        let source = try normalizedSource(image)
        let rgba = try rgbaPixels(from: source)
        let iconMask = close(dilate(createIconMask(from: rgba, width: source.width, height: source.height)))
        let circleMask = makeCircleMask(width: source.width, height: source.height)
        let usableMask = zip(circleMask, iconMask).map { circle, icon in
            circle == 255 && icon == 0 ? UInt8(255) : UInt8(0)
        }
        let iconMaskedPixels = zip(circleMask, iconMask).filter { $0 == 255 && $1 == 255 }.count
        let circlePixels = circleMask.filter { $0 == 255 }.count
        let usablePixels = usableMask.filter { $0 == 255 }.count

        return BGIMiniMapPreprocessResult(
            sourceImage: source,
            iconMaskImage: try maskImage(from: iconMask, width: source.width, height: source.height),
            usableMaskImage: try maskImage(from: usableMask, width: source.width, height: source.height),
            iconMask: iconMask,
            usableMask: usableMask,
            statistics: BGIMiniMapPreprocessStatistics(
                iconMaskedPixels: iconMaskedPixels,
                circlePixels: circlePixels,
                usablePixels: usablePixels
            )
        )
    }

    func makeMatchInput(
        from preprocess: BGIMiniMapPreprocessResult,
        orientation: BGIMiniMapOrientationEstimate
    ) throws -> BGIMiniMapMatchInput {
        let source = try rgbaPixels(from: preprocess.sourceImage)
        let processed = applyProcess2ImageTransform(source, angleDegrees: orientation.degrees)
        let bgMask = createBackgroundMask(from: processed)
        let circleMask = makeCircleMask(width: BGIMiniMapConstants.originalSize, height: BGIMiniMapConstants.originalSize)
        let invertedIconMask = preprocess.iconMask.map { $0 == 255 ? UInt8(0) : UInt8(255) }
        let finalMask = zip3(circleMask, invertedIconMask, bgMask).map { circle, nonIcon, background in
            circle == 255 && nonIcon == 255 && background == 255 ? UInt8(255) : UInt8(0)
        }
        let bgSeedPixels = backgroundSeedMask(from: processed).filter { $0 == 255 }.count
        let bgExpandedPixels = bgMask.filter { $0 == 255 }.count
        let finalMaskPixels = finalMask.filter { $0 == 255 }.count

        return BGIMiniMapMatchInput(
            processedImage: try rgbaImage(from: processed, width: BGIMiniMapConstants.originalSize, height: BGIMiniMapConstants.originalSize),
            finalMaskImage: try maskImage(from: finalMask, width: BGIMiniMapConstants.originalSize, height: BGIMiniMapConstants.originalSize),
            backgroundMaskImage: try maskImage(from: bgMask, width: BGIMiniMapConstants.originalSize, height: BGIMiniMapConstants.originalSize),
            finalMask: finalMask,
            backgroundMask: bgMask,
            statistics: BGIMiniMapMatchInputStatistics(
                finalMaskPixels: finalMaskPixels,
                backgroundSeedPixels: bgSeedPixels,
                backgroundExpandedPixels: bgExpandedPixels
            )
        )
    }

    private func normalizedSource(_ image: CGImage) throws -> CGImage {
        let side = BGIMiniMapConstants.originalSize
        guard image.width != side || image.height != side else {
            return image
        }
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: side * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let resized = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return resized
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return rgba
    }

    private func createIconMask(from rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let r = Int(rgba[offset])
            let g = Int(rgba[offset + 1])
            let b = Int(rgba[offset + 2])
            let cmax = max(r, g, b)
            let cmin = min(r, g, b)
            let equalMidGray = cmax == cmin && cmax >= 50 && cmax <= 127
            let diff = cmax - cmin
            let inverseMax = 255 - cmax
            let denominator = min(inverseMax / 6, diff) + 10
            let numerator = equalMidGray ? 255 : cmax
            let score = Double(numerator) / Double(max(1, denominator)) * 10.0
            mask[pixel] = score > 200 ? 255 : 0
        }
        return mask
    }

    private func applyProcess2ImageTransform(_ rgba: [UInt8], angleDegrees: Double) -> [UInt8] {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        let center = Double(width) / 2.0
        var output = rgba
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let dx = Double(x) - center
                let dy = Double(y) - center
                let radius = sqrt(dx * dx + dy * dy)
                let sectorAlpha = sectorMaskValue(radius: radius, x: dx, y: dy, angleDegrees: angleDegrees)
                let alpha1 = alphaMask1Value(radius: radius)
                for channel in 0..<3 {
                    let source = Double(rgba[offset + channel])
                    let sectorAdjusted = (source - 255.0) / max(1.0, sectorAlpha) * 255.0 + 255.0
                    let alphaAdjusted = sectorAdjusted / max(1.0, alpha1) * 255.0
                    output[offset + channel] = UInt8(max(0, min(255, alphaAdjusted.rounded())))
                }
                output[offset + 3] = 255
            }
        }
        return output
    }

    private func sectorMaskValue(radius: Double, x: Double, y: Double, angleDegrees: Double) -> Double {
        let alpha2 = min(255.0, 137.0 + 1.43 * radius)
        let pointAngle = normalizedDegrees(atan2(y, x) * 180.0 / .pi)
        let start = normalizedDegrees(angleDegrees.rounded() + 45.5)
        let end = normalizedDegrees(angleDegrees.rounded() + 314.5)
        return angle(pointAngle, isInClockwiseSectorFrom: start, to: end) ? 255.0 : alpha2
    }

    private func alphaMask1Value(radius: Double) -> Double {
        let params = [18.632, 20.157, 24.093, 34.617, 38.566, 41.94, 47.654, 51.087, 58.561, 63.925, 67.759, 71.77, 75.214]
        let insertion = params.firstIndex { radius < $0 } ?? params.count
        return Double(min(229 + insertion, 255))
    }

    private func angle(_ value: Double, isInClockwiseSectorFrom start: Double, to end: Double) -> Bool {
        if start <= end {
            return value >= start && value <= end
        }
        return value >= start || value <= end
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private func createBackgroundMask(from rgba: [UInt8]) -> [UInt8] {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        let seed = open2x2(backgroundSeedMask(from: rgba), width: width, height: height)
        guard seed.contains(255) else {
            return [UInt8](repeating: 255, count: width * height)
        }

        var minDist = [UInt8](repeating: 255, count: 256)
        for y in 0..<height {
            for x in 0..<width where seed[y * width + x] == 255 {
                let radius = radiusByte(x: x, y: y, width: width, height: height)
                let angle = angleByte(x: x, y: y, width: width, height: height)
                if minDist[Int(angle)] > radius {
                    minDist[Int(angle)] = radius
                }
            }
        }

        var radialMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let radius = radiusByte(x: x, y: y, width: width, height: height)
                let angle = angleByte(x: x, y: y, width: width, height: height)
                radialMask[y * width + x] = radius < minDist[Int(angle)] ? 255 : 0
            }
        }

        let brightMask = brightAllChannelsMask(from: rgba)
        return zip(brightMask, radialMask).map { bright, radial in
            bright == 255 || radial == 255 ? UInt8(255) : UInt8(0)
        }
    }

    private func backgroundSeedMask(from rgba: [UInt8]) -> [UInt8] {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        var mask = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let red = rgba[offset]
            let green = rgba[offset + 1]
            let blue = rgba[offset + 2]
            mask[pixel] = blue >= 165 && blue <= 180
                && green >= 165 && green <= 180
                && red >= 55 && red <= 75
                ? 255
                : 0
        }
        return mask
    }

    private func brightAllChannelsMask(from rgba: [UInt8]) -> [UInt8] {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        var mask = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            mask[pixel] = rgba[offset] >= 100 && rgba[offset + 1] >= 100 && rgba[offset + 2] >= 100
                ? 255
                : 0
        }
        return mask
    }

    private func radiusByte(x: Int, y: Int, width: Int, height: Int) -> UInt8 {
        let dx = Double(x) - Double(width) / 2.0
        let dy = Double(y) - Double(height) / 2.0
        return UInt8(max(0, min(255, sqrt(dx * dx + dy * dy).rounded())))
    }

    private func angleByte(x: Int, y: Int, width: Int, height: Int) -> UInt8 {
        let dx = Double(x) - Double(width) / 2.0
        let dy = Double(y) - Double(height) / 2.0
        let degrees = normalizedDegrees(atan2(dy, dx) * 180.0 / .pi)
        return UInt8(max(0, min(255, (degrees / 2.0).rounded())))
    }

    private func makeCircleMask(width: Int, height: Int) -> [UInt8] {
        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let radius = Double(min(width, height)) / 2.0
        let radiusSquared = radius * radius
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - centerX
                let dy = Double(y) - centerY
                if dx * dx + dy * dy <= radiusSquared {
                    mask[y * width + x] = 255
                }
            }
        }
        return mask
    }

    private func dilate(_ mask: [UInt8]) -> [UInt8] {
        morph(mask, mode: .dilate)
    }

    private func close(_ mask: [UInt8]) -> [UInt8] {
        morph(morph(mask, mode: .dilate), mode: .erode)
    }

    private func open2x2(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        dilate2x2(erode2x2(mask, width: width, height: height), width: width, height: height)
    }

    private func erode2x2(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let allHit = [(0, 0), (1, 0), (0, 1), (1, 1)].allSatisfy { dx, dy in
                    let nx = x + dx
                    let ny = y + dy
                    return nx < width && ny < height && mask[ny * width + nx] == 255
                }
                output[y * width + x] = allHit ? 255 : 0
            }
        }
        return output
    }

    private func dilate2x2(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let hit = [(0, 0), (-1, 0), (0, -1), (-1, -1)].contains { dx, dy in
                    let nx = x + dx
                    let ny = y + dy
                    return nx >= 0 && ny >= 0 && mask[ny * width + nx] == 255
                }
                output[y * width + x] = hit ? 255 : 0
            }
        }
        return output
    }

    private enum MorphMode {
        case dilate
        case erode
    }

    private func morph(_ mask: [UInt8], mode: MorphMode) -> [UInt8] {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        let kernel = [
            (0, -2),
            (-1, -1), (0, -1), (1, -1),
            (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
            (-1, 1), (0, 1), (1, 1),
            (0, 2)
        ]
        var output = [UInt8](repeating: mode == .erode ? 255 : 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var hit = false
                var allHit = true
                for (dx, dy) in kernel {
                    let nx = x + dx
                    let ny = y + dy
                    let value: UInt8
                    if nx < 0 || ny < 0 || nx >= width || ny >= height {
                        value = 0
                    } else {
                        value = mask[ny * width + nx]
                    }
                    hit = hit || value == 255
                    allHit = allHit && value == 255
                }
                output[y * width + x] = mode == .dilate
                    ? (hit ? 255 : 0)
                    : (allHit ? 255 : 0)
            }
        }
        return output
    }

    private func maskImage(from mask: [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        for pixel in 0..<(width * height) {
            let value = mask[pixel]
            let offset = pixel * bytesPerPixel
            rgba[offset] = value
            rgba[offset + 1] = value
            rgba[offset + 2] = value
            rgba[offset + 3] = 255
        }
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return image
    }

    private func rgbaImage(from rgba: [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = rgba
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return image
    }

    private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
        zip(zip(a, b), c).map { ab, cValue in
            (ab.0, ab.1, cValue)
        }
    }
}

/// Swift port of BetterGI `CameraOrientationCalculator.PredictRotation`.
///
/// The algorithm remaps the annulus around the character arrow into polar
/// coordinates, builds two hue/luma histograms, and scores every angle by how
/// well the remapped samples explain the two alpha-corrected luma variants.
struct BGIMiniMapOrientationEstimator: Sendable {
    private let tplOutRad = 78.0
    private let tplInnRad = 19.0
    private let rLength = 60
    private let thetaLength = 360
    private let fLength = 256
    private let scale = 2

    func estimate(_ preprocess: BGIMiniMapPreprocessResult) throws -> BGIMiniMapOrientationEstimate {
        let size = BGIMiniMapConstants.originalSize
        let rgba = try rgbaPixels(from: preprocess.sourceImage)
        let rArray = linearSpaced(tplInnRad, tplOutRad, rLength)
        let thetaArray = linearSpaced(0, 360, thetaLength, endpoint: false)
        let alphaMask1 = rArray.map(alphaMask1Value)
        let alphaMask2 = rArray.map { 137.0 + 1.43 * $0 }
        var hue = [Double](repeating: 0, count: thetaLength * rLength)
        var fa = [Double](repeating: 0, count: thetaLength * rLength)
        var fb = [Double](repeating: 0, count: thetaLength * rLength)

        for thetaIndex in 0..<thetaLength {
            let radians = thetaArray[thetaIndex] * .pi / 180.0
            let cosTheta = cos(radians)
            let sinTheta = sin(radians)
            for radiusIndex in 0..<rLength {
                let radius = rArray[radiusIndex]
                let x = radius * cosTheta + Double(size) / 2.0
                let y = radius * sinTheta + Double(size) / 2.0
                let sample = sampleRGBA(rgba, width: size, height: size, x: x, y: y)
                let mask = nearestMask(preprocess.iconMask, width: size, height: size, x: x, y: y)
                let gray = gray(red: sample.red, green: sample.green, blue: sample.blue)
                let index = thetaIndex * rLength + radiusIndex
                hue[index] = hueFull(red: sample.red, green: sample.green, blue: sample.blue)

                let alpha1 = alphaMask1[radiusIndex]
                let alpha2 = alphaMask2[radiusIndex]
                let faValue = gray / alpha1 * 255.0
                let temp = (gray - 255.0) / alpha2 * 255.0 + 255.0
                let fbValue = temp / alpha1 * 255.0
                fa[index] = mask == 255 ? gray : faValue
                fb[index] = mask == 255 ? temp : fbValue
            }
        }

        let histA = makeHistogram(hue: hue, luma: fa)
        let histB = makeHistogram(hue: hue, luma: fb)
        var result = [Double](repeating: 0, count: thetaLength)
        for i in 0..<(thetaLength * rLength) {
            let h = hue[i]
            let faValue = fa[i]
            let fbValue = fb[i]
            guard h >= 0, h < 256, faValue >= 0, fbValue < 256 else { continue }
            let thetaIndex = i / rLength
            if faValue >= 256 {
                result[thetaIndex] += 255.0
            } else if fbValue < 0 {
                result[thetaIndex] -= 255.0
            } else {
                let hIndex = min(255, max(0, Int(h / 256.0 * Double(fLength))))
                let faIndex = min(255, max(0, Int(faValue / 256.0 * Double(fLength))))
                let fbIndex = min(255, max(0, Int(fbValue / 256.0 * Double(fLength))))
                let ha = histA[hIndex * fLength + faIndex]
                let hb = histB[hIndex * fLength + fbIndex]
                if ha > hb {
                    result[thetaIndex] += 0.0
                } else if abs(ha - hb) < 0.0001 {
                    result[thetaIndex] += 100.0
                } else {
                    result[thetaIndex] += 255.0
                }
            }
        }

        let upsampled = upsampleLinear(result, factor: scale)
        let peakWidth = thetaLength / 4 * scale + 1
        let shifted = rightShift(upsampled, by: peakWidth)
        let peakRegionSum = shifted.prefix(peakWidth).reduce(0, +)
        var integral = [Double](repeating: 0, count: upsampled.count + 1)
        for i in 0..<upsampled.count {
            integral[i + 1] = integral[i] + upsampled[i] - shifted[i]
        }
        guard let maxPair = integral.enumerated().max(by: { $0.element < $1.element }) else {
            return BGIMiniMapOrientationEstimate(degrees: 0, confidence: 0)
        }
        let degree = Double(maxPair.offset - 1) / Double(thetaLength) * 360.0 / Double(scale) - 45.0
        let confidence = (maxPair.element + peakRegionSum) / Double(peakWidth * rLength * 255)
        return BGIMiniMapOrientationEstimate(degrees: normalizedDegrees(degree), confidence: confidence)
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return rgba
    }

    private func linearSpaced(_ a: Double, _ b: Double, _ n: Int, endpoint: Bool = true) -> [Double] {
        guard n > 0 else { return [] }
        guard n > 1 else { return [a] }
        let intervalCount = endpoint ? n - 1 : n
        let step = (b - a) / Double(intervalCount)
        var values: [Double] = []
        values.reserveCapacity(n)
        for i in 0..<n {
            values.append(a + Double(i) * step)
        }
        return values
    }

    private func alphaMask1Value(radius: Double) -> Double {
        let params = [18.632, 20.157, 24.093, 34.617, 38.566, 41.94, 47.654, 51.087, 58.561, 63.925, 67.759, 71.77, 75.214]
        let insertion = params.firstIndex { radius < $0 } ?? params.count
        return Double(min(229 + insertion, 255))
    }

    private func makeHistogram(hue: [Double], luma: [Double]) -> [Double] {
        var hist = [Double](repeating: 0, count: fLength * fLength)
        for i in 0..<hue.count {
            let h = hue[i]
            let v = luma[i]
            guard h >= 0, h < 256, v >= 0, v < 256 else { continue }
            let hIndex = min(255, max(0, Int(h / 256.0 * Double(fLength))))
            let vIndex = min(255, max(0, Int(v / 256.0 * Double(fLength))))
            hist[hIndex * fLength + vIndex] += 1
        }
        return hist
    }

    private func sampleRGBA(_ rgba: [UInt8], width: Int, height: Int, x: Double, y: Double) -> (red: Double, green: Double, blue: Double) {
        let clampedX = min(Double(width - 1), max(0, x))
        let clampedY = min(Double(height - 1), max(0, y))
        let x0 = Int(floor(clampedX))
        let y0 = Int(floor(clampedY))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = clampedX - Double(x0)
        let ty = clampedY - Double(y0)
        let c00 = pixel(rgba, width: width, x: x0, y: y0)
        let c10 = pixel(rgba, width: width, x: x1, y: y0)
        let c01 = pixel(rgba, width: width, x: x0, y: y1)
        let c11 = pixel(rgba, width: width, x: x1, y: y1)
        return (
            bilerp(c00.red, c10.red, c01.red, c11.red, tx: tx, ty: ty),
            bilerp(c00.green, c10.green, c01.green, c11.green, tx: tx, ty: ty),
            bilerp(c00.blue, c10.blue, c01.blue, c11.blue, tx: tx, ty: ty)
        )
    }

    private func pixel(_ rgba: [UInt8], width: Int, x: Int, y: Int) -> (red: Double, green: Double, blue: Double) {
        let offset = (y * width + x) * 4
        return (Double(rgba[offset]), Double(rgba[offset + 1]), Double(rgba[offset + 2]))
    }

    private func bilerp(_ c00: Double, _ c10: Double, _ c01: Double, _ c11: Double, tx: Double, ty: Double) -> Double {
        let top = c00 * (1 - tx) + c10 * tx
        let bottom = c01 * (1 - tx) + c11 * tx
        return top * (1 - ty) + bottom * ty
    }

    private func nearestMask(_ mask: [UInt8], width: Int, height: Int, x: Double, y: Double) -> UInt8 {
        let ix = min(width - 1, max(0, Int(x.rounded())))
        let iy = min(height - 1, max(0, Int(y.rounded())))
        return mask[iy * width + ix]
    }

    private func gray(red: Double, green: Double, blue: Double) -> Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    private func hueFull(red: Double, green: Double, blue: Double) -> Double {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        guard delta > 0 else { return 0 }
        let hueDegrees: Double
        if maxValue == red {
            hueDegrees = 60.0 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maxValue == green {
            hueDegrees = 60.0 * ((blue - red) / delta + 2.0)
        } else {
            hueDegrees = 60.0 * ((red - green) / delta + 4.0)
        }
        let normalized = hueDegrees < 0 ? hueDegrees + 360.0 : hueDegrees
        return normalized / 360.0 * 255.0
    }

    private func upsampleLinear(_ values: [Double], factor: Int) -> [Double] {
        guard factor > 1 else { return values }
        var output = [Double](repeating: 0, count: values.count * factor)
        for i in 0..<output.count {
            let position = Double(i) / Double(factor)
            let lower = Int(floor(position)) % values.count
            let upper = (lower + 1) % values.count
            let t = position - floor(position)
            output[i] = values[lower] * (1 - t) + values[upper] * t
        }
        return output
    }

    private func rightShift(_ values: [Double], by amount: Int) -> [Double] {
        let shift = amount % values.count
        return Array(values[(values.count - shift)..<values.count]) + Array(values[0..<(values.count - shift)])
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
