import CoreGraphics
import Foundation
import ImageIO

struct TemplateRecognitionReport: Equatable, Sendable {
    let observations: [RecognitionObservation]
    let objectCount: Int
    let matchedCount: Int
    let costMs: Double
    let backendName: String
}

final class TemplateMatchingRecognitionEngine {
    private var templateCache: [TemplateCacheKey: MatchImage] = [:]

    func recognize(
        imageFrame: CaptureImageFrame,
        objects: [RecognitionObject]
    ) -> TemplateRecognitionReport {
        let startedAt = Date()
        guard let source = MatchImage(cgImage: imageFrame.cgImage) else {
            return TemplateRecognitionReport(observations: [], objectCount: 0, matchedCount: 0, costMs: 0, backendName: "swiftFallback")
        }

        let templateObjects = objects.filter {
            $0.recognitionType == .templateMatch && $0.templateAssetName != nil
        }
        let observations = templateObjects.flatMap { object in
            templateObservations(for: object, in: source, frame: imageFrame.metadata)
        }

        return TemplateRecognitionReport(
            observations: observations,
            objectCount: templateObjects.count,
            matchedCount: observations.count,
            costMs: Date().timeIntervalSince(startedAt) * 1000,
            backendName: "swiftFallback"
        )
    }

    private func templateObservations(
        for object: RecognitionObject,
        in source: MatchImage,
        frame: CapturedFrame
    ) -> [RecognitionObservation] {
        let matches: [TemplateMatchResult]
        if object.maxMatchCount > 1 {
            matches = multiMatches(for: object, in: source, frame: frame, maxCount: object.maxMatchCount)
        } else if let match = bestMatch(for: object, in: source, frame: frame),
                  match.score >= object.threshold {
            matches = [match]
        } else {
            matches = []
        }

        return matches.enumerated().map { index, match in
            let normalizedRect = CGRect(
                x: Double(match.rect.minX) / Double(source.width),
                y: Double(match.rect.minY) / Double(source.height),
                width: Double(match.rect.width) / Double(source.width),
                height: Double(match.rect.height) / Double(source.height)
            )
            let suffix = matches.count == 1 ? "" : "-\(index)"
            return RecognitionObservation(
                id: "\(object.id)-\(frame.frameIndex)\(suffix)",
                objectID: object.id,
                objectName: object.name ?? object.id,
                recognitionType: object.recognitionType,
                normalizedRect: normalizedRect,
                confidence: match.score,
                text: nil,
                frameIndex: frame.frameIndex,
                timestamp: frame.timestamp
            )
        }
    }

    private func bestMatch(
        for object: RecognitionObject,
        in source: MatchImage,
        frame: CapturedFrame
    ) -> TemplateMatchResult? {
        guard let template = templateImage(for: object, use3Channels: object.use3Channels, sourceWidth: source.width),
              template.width <= source.width,
              template.height <= source.height else {
            return nil
        }

        let searchRect = clampedSearchRect(for: object, frame: frame, source: source, template: template)
        guard searchRect.width >= template.width, searchRect.height >= template.height else {
            return nil
        }

        let candidateCount = max(1, (searchRect.width - template.width + 1) * (searchRect.height - template.height + 1))
        let coarseStep = max(1, Int(sqrt(Double(candidateCount) / 12_000.0)))
        guard let coarse = scan(
            source: source,
            template: template,
            searchRect: searchRect,
            mode: object.templateMatchMode,
            step: coarseStep,
            useSample: true
        ) else {
            return nil
        }

        let refineRadius = max(2, coarseStep * 2)
        let minRefineX = max(searchRect.minX, coarse.point.x - refineRadius)
        let minRefineY = max(searchRect.minY, coarse.point.y - refineRadius)
        let maxRefineX = min(searchRect.maxX - template.width + 1, coarse.point.x + refineRadius)
        let maxRefineY = min(searchRect.maxY - template.height + 1, coarse.point.y + refineRadius)
        let refineRect = CGRect(
            x: minRefineX,
            y: minRefineY,
            width: maxRefineX - minRefineX + 1,
            height: maxRefineY - minRefineY + 1
        ).integral

        let refined = scan(
            source: source,
            template: template,
            searchRect: MatchRect(refineRect),
            mode: object.templateMatchMode,
            step: 1,
            useSample: false
        ) ?? coarse

        let selected: ScoredPoint
        if refined.score < object.threshold,
           candidateCount <= 800_000,
           let exhaustive = scan(
            source: source,
            template: template,
            searchRect: searchRect,
            mode: object.templateMatchMode,
            step: 1,
            useSample: false
           ) {
            selected = exhaustive
        } else {
            selected = refined
        }

        return TemplateMatchResult(
            score: selected.score,
            rect: MatchRect(
                x: selected.point.x,
                y: selected.point.y,
                width: template.width,
                height: template.height
            )
        )
    }

    private func multiMatches(
        for object: RecognitionObject,
        in source: MatchImage,
        frame: CapturedFrame,
        maxCount: Int
    ) -> [TemplateMatchResult] {
        guard maxCount > 0,
              let template = templateImage(for: object, use3Channels: object.use3Channels, sourceWidth: source.width),
              template.width <= source.width,
              template.height <= source.height else {
            return []
        }

        let searchRect = clampedSearchRect(for: object, frame: frame, source: source, template: template)
        guard searchRect.width >= template.width, searchRect.height >= template.height else {
            return []
        }

        let candidates = scanCandidates(
            source: source,
            template: template,
            searchRect: searchRect,
            mode: object.templateMatchMode,
            threshold: object.threshold
        )
        return suppressOverlappingMatches(candidates, maxCount: maxCount)
            .sorted { lhs, rhs in
                if lhs.rect.minY != rhs.rect.minY {
                    return lhs.rect.minY < rhs.rect.minY
                }
                return lhs.rect.minX < rhs.rect.minX
            }
    }

    private func templateImage(for object: RecognitionObject, use3Channels: Bool, sourceWidth: Int) -> MatchImage? {
        guard let assetName = object.templateAssetName else { return nil }
        let scalePermille = Int((BGIAssetResolver.assetScale(forFrameWidth: sourceWidth) * 1000).rounded())
        let key = TemplateCacheKey(assetName: assetName, use3Channels: use3Channels, scalePermille: scalePermille)
        if let cached = templateCache[key] {
            return cached
        }
        guard let cgImage = try? BGIAssetResolver.scaledTemplateImage(for: assetName, frameWidth: sourceWidth),
              let image = MatchImage(cgImage: cgImage, forceRGB: use3Channels, ignoresTransparentPixels: true) else {
            return nil
        }
        templateCache[key] = image
        return image
    }

    private func clampedSearchRect(
        for object: RecognitionObject,
        frame: CapturedFrame,
        source: MatchImage,
        template: MatchImage
    ) -> MatchRect {
        let full = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let rawRect: CGRect
        if let roi = object.regionOfInterest {
            let normalized = roi.normalizedRect()
            rawRect = CGRect(
                x: normalized.minX * Double(source.width),
                y: normalized.minY * Double(source.height),
                width: normalized.width * Double(source.width),
                height: normalized.height * Double(source.height)
            )
        } else {
            rawRect = full
        }

        var rect = rawRect.intersection(full).integral
        if rect.width < Double(template.width) || rect.height < Double(template.height) {
            rect = full
        }
        return MatchRect(rect)
    }

    private func scan(
        source: MatchImage,
        template: MatchImage,
        searchRect: MatchRect,
        mode: TemplateMatchMode,
        step: Int,
        useSample: Bool
    ) -> ScoredPoint? {
        let maxX = searchRect.maxX - template.width + 1
        let maxY = searchRect.maxY - template.height + 1
        guard maxX >= searchRect.minX, maxY >= searchRect.minY else { return nil }

        let samples = useSample ? template.sampleIndices : nil
        var best: ScoredPoint?
        var y = searchRect.minY
        while y <= maxY {
            var x = searchRect.minX
            while x <= maxX {
                let score = scoreAt(
                    x: x,
                    y: y,
                    source: source,
                    template: template,
                    mode: mode,
                    samples: samples
                )
                if best == nil || score > best!.score {
                    best = ScoredPoint(point: MatchPoint(x: x, y: y), score: score)
                }
                x += step
            }
            y += step
        }
        return best
    }

    private func scanCandidates(
        source: MatchImage,
        template: MatchImage,
        searchRect: MatchRect,
        mode: TemplateMatchMode,
        threshold: Double
    ) -> [TemplateMatchResult] {
        let maxX = searchRect.maxX - template.width + 1
        let maxY = searchRect.maxY - template.height + 1
        guard maxX >= searchRect.minX, maxY >= searchRect.minY else { return [] }

        var candidates: [TemplateMatchResult] = []
        var y = searchRect.minY
        while y <= maxY {
            var x = searchRect.minX
            while x <= maxX {
                let score = scoreAt(
                    x: x,
                    y: y,
                    source: source,
                    template: template,
                    mode: mode,
                    samples: nil
                )
                if score >= threshold {
                    candidates.append(TemplateMatchResult(
                        score: score,
                        rect: MatchRect(x: x, y: y, width: template.width, height: template.height)
                    ))
                }
                x += 1
            }
            y += 1
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.rect.minY != rhs.rect.minY {
                return lhs.rect.minY < rhs.rect.minY
            }
            return lhs.rect.minX < rhs.rect.minX
        }
    }

    private func suppressOverlappingMatches(
        _ candidates: [TemplateMatchResult],
        maxCount: Int
    ) -> [TemplateMatchResult] {
        var selected: [TemplateMatchResult] = []
        for candidate in candidates {
            guard selected.count < maxCount else { break }
            if selected.contains(where: { $0.rect.intersects(candidate.rect) }) {
                continue
            }
            selected.append(candidate)
        }
        return selected
    }

    private func scoreAt(
        x: Int,
        y: Int,
        source: MatchImage,
        template: MatchImage,
        mode: TemplateMatchMode,
        samples: [Int]?
    ) -> Double {
        let indices = samples ?? template.allIndices
        guard !indices.isEmpty else { return 0 }

        switch mode {
        case .cCoeffNormed:
            return cCoeffNormedScore(x: x, y: y, source: source, template: template, indices: indices)
        case .cCorrNormed:
            return cCorrNormedScore(x: x, y: y, source: source, template: template, indices: indices)
        case .sqDiffNormed:
            return sqDiffNormedSimilarity(x: x, y: y, source: source, template: template, indices: indices)
        }
    }

    private func cCoeffNormedScore(
        x: Int,
        y: Int,
        source: MatchImage,
        template: MatchImage,
        indices: [Int]
    ) -> Double {
        var sourceSum = 0.0
        var templateSum = 0.0
        for index in indices {
            sourceSum += Double(source.value(atTemplateValueIndex: index, originX: x, originY: y, template: template))
            templateSum += Double(template.values[index])
        }
        let count = Double(indices.count)
        let sourceMean = sourceSum / count
        let templateMean = templateSum / count

        var numerator = 0.0
        var sourceSq = 0.0
        var templateSq = 0.0
        for index in indices {
            let sourceValue = Double(source.value(atTemplateValueIndex: index, originX: x, originY: y, template: template)) - sourceMean
            let templateValue = Double(template.values[index]) - templateMean
            numerator += sourceValue * templateValue
            sourceSq += sourceValue * sourceValue
            templateSq += templateValue * templateValue
        }
        let denominator = sqrt(sourceSq * templateSq)
        guard denominator > 0 else { return 0 }
        return max(-1, min(1, numerator / denominator))
    }

    private func cCorrNormedScore(
        x: Int,
        y: Int,
        source: MatchImage,
        template: MatchImage,
        indices: [Int]
    ) -> Double {
        var numerator = 0.0
        var sourceSq = 0.0
        var templateSq = 0.0
        for index in indices {
            let sourceValue = Double(source.value(atTemplateValueIndex: index, originX: x, originY: y, template: template))
            let templateValue = Double(template.values[index])
            numerator += sourceValue * templateValue
            sourceSq += sourceValue * sourceValue
            templateSq += templateValue * templateValue
        }
        let denominator = sqrt(sourceSq * templateSq)
        guard denominator > 0 else { return 0 }
        return max(0, min(1, numerator / denominator))
    }

    private func sqDiffNormedSimilarity(
        x: Int,
        y: Int,
        source: MatchImage,
        template: MatchImage,
        indices: [Int]
    ) -> Double {
        var diffSq = 0.0
        var sourceSq = 0.0
        var templateSq = 0.0
        for index in indices {
            let sourceValue = Double(source.value(atTemplateValueIndex: index, originX: x, originY: y, template: template))
            let templateValue = Double(template.values[index])
            let diff = sourceValue - templateValue
            diffSq += diff * diff
            sourceSq += sourceValue * sourceValue
            templateSq += templateValue * templateValue
        }
        let denominator = sqrt(sourceSq * templateSq)
        guard denominator > 0 else { return 0 }
        let normalizedDistance = min(1, diffSq / denominator)
        return 1 - normalizedDistance
    }
}

private struct TemplateCacheKey: Hashable {
    let assetName: String
    let use3Channels: Bool
    let scalePermille: Int
}

private struct TemplateMatchResult {
    let score: Double
    let rect: MatchRect
}

private struct ScoredPoint {
    let point: MatchPoint
    let score: Double
}

private struct MatchPoint {
    let x: Int
    let y: Int
}

private struct MatchRect: Equatable {
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int

    var maxX: Int { minX + width - 1 }
    var maxY: Int { minY + height - 1 }

    init(x: Int, y: Int, width: Int, height: Int) {
        minX = x
        minY = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    init(_ rect: CGRect) {
        minX = max(0, Int(rect.minX))
        minY = max(0, Int(rect.minY))
        width = max(0, Int(rect.width))
        height = max(0, Int(rect.height))
    }

    func intersects(_ other: MatchRect) -> Bool {
        guard width > 0, height > 0, other.width > 0, other.height > 0 else {
            return false
        }
        return minX <= other.maxX
            && other.minX <= maxX
            && minY <= other.maxY
            && other.minY <= maxY
    }
}

private struct MatchImage {
    let width: Int
    let height: Int
    let channelCount: Int
    let values: [Float]
    let allIndices: [Int]
    let sampleIndices: [Int]

    init?(cgImage: CGImage, forceRGB: Bool = false, ignoresTransparentPixels: Bool = false) {
        width = cgImage.width
        height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
              ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        channelCount = forceRGB ? 3 : 1
        var values = [Float]()
        values.reserveCapacity(width * height * channelCount)
        var activeIndices: [Int] = []
        activeIndices.reserveCapacity(width * height * channelCount)
        for pixelIndex in 0..<(width * height) {
            let rgbaIndex = pixelIndex * 4
            let red = Float(rgba[rgbaIndex])
            let green = Float(rgba[rgbaIndex + 1])
            let blue = Float(rgba[rgbaIndex + 2])
            let alpha = rgba[rgbaIndex + 3]
            let includePixel = !ignoresTransparentPixels || alpha >= 16
            if forceRGB {
                values.append(red)
                values.append(green)
                values.append(blue)
                if includePixel {
                    activeIndices.append(pixelIndex * channelCount)
                    activeIndices.append(pixelIndex * channelCount + 1)
                    activeIndices.append(pixelIndex * channelCount + 2)
                }
            } else {
                values.append(0.299 * red + 0.587 * green + 0.114 * blue)
                if includePixel {
                    activeIndices.append(pixelIndex * channelCount)
                }
            }
        }
        self.values = values
        allIndices = activeIndices.isEmpty ? Array(values.indices) : activeIndices
        sampleIndices = MatchImage.makeSampleIndices(
            from: allIndices,
            maxCount: 96
        )
    }

    func value(atTemplateValueIndex index: Int, originX: Int, originY: Int, template: MatchImage) -> Float {
        let templatePixel = index / template.channelCount
        let channel = index % template.channelCount
        let templateY = templatePixel / template.width
        let templateX = templatePixel % template.width
        let sourcePixel = (originY + templateY) * width + (originX + templateX)
        let sourceChannel = min(channel, channelCount - 1)
        return values[sourcePixel * channelCount + sourceChannel]
    }

    private static func makeSampleIndices(from allIndices: [Int], maxCount: Int) -> [Int] {
        guard allIndices.count > maxCount else {
            return allIndices
        }

        let stride = max(1, Int(ceil(Double(allIndices.count) / Double(maxCount))))
        var indices: [Int] = []
        indices.reserveCapacity(maxCount)
        var index = 0
        while index < allIndices.count {
            indices.append(allIndices[index])
            index += stride
        }
        return indices
    }
}
