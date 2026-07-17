import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI mini map matcher")
struct BGIMiniMapMatcherTests {
    @Test("Layer descriptors decode upstream map json casing")
    func layerDescriptorsDecodeUpstreamJson() throws {
        let json = """
        [
          {
            "LayerGroupId": "37001",
            "LayerId": "LayeredMap_3700101",
            "Name": "月矩力试验设计局",
            "Scale": 3,
            "Floor": 5,
            "Left": 10096.5,
            "Top": 3464.0,
            "IsOverSize": true
          }
        ]
        """

        let descriptors = try BGIMiniMapLayerDescriptor.decodeList(from: Data(json.utf8))

        let descriptor = try #require(descriptors.first)
        #expect(descriptor.layerGroupId == "37001")
        #expect(descriptor.layerId == "LayeredMap_3700101")
        #expect(descriptor.scale == 3)
        #expect(descriptor.left == 10096.5)
        #expect(descriptor.isOverSize == true)
    }

    @Test("Rough matcher finds embedded color mini map")
    func roughMatcherFindsEmbeddedColorMiniMap() throws {
        let template = makePattern(width: 52, height: 52, channels: 3)
        let source = embed(template, inWidth: 128, height: 128, atX: 37, y: 42)
        let prepared = makePreparedTemplate(rough: template)
        let layer = makeLayer(coarse: source)

        let result = try #require(layer.roughMatch(prepared))

        #expect(result.sourcePoint == CGPoint(x: 37, y: 42))
        #expect(result.confidence > 0.99)
        let world = layer.mapToWorld(result.sourcePoint, zoom: Double(BGIMiniMapConstants.roughZoom), miniMapSize: BGIMiniMapConstants.roughMatchSize)
        #expect(layer.worldToMap(world, zoom: Double(BGIMiniMapConstants.roughZoom)) == CGPoint(x: 63, y: 68))
    }

    @Test("Exact matcher finds embedded gray mini map near previous world point")
    func exactMatcherFindsEmbeddedGrayMiniMapNearPreviousPoint() throws {
        let template = makePattern(width: 260, height: 260, channels: 1)
        let expected = CGPoint(x: 5, y: 5)
        let source = embed(template, inWidth: 270, height: 270, atX: Int(expected.x), y: Int(expected.y))
        let layer = makeLayer(fine: source)
        let prepared = makePreparedTemplate(exact: template)
        let nearWorld = layer.mapToWorld(expected, zoom: Double(BGIMiniMapConstants.exactZoom), miniMapSize: BGIMiniMapConstants.exactMatchSize)

        let result = try #require(layer.exactMatch(prepared, near: nearWorld))

        #expect(result.sourcePoint == expected)
        #expect(result.confidence > 0.99)
    }

    private func makeLayer(
        coarse: PixelImage = PixelImage(width: 64, height: 64, channelCount: 3, values: [Double](repeating: 0, count: 64 * 64 * 3)),
        fine: PixelImage = PixelImage(width: 300, height: 300, channelCount: 1, values: [Double](repeating: 0, count: 300 * 300))
    ) -> BGIMiniMapTemplateLayer {
        BGIMiniMapTemplateLayer(
            descriptor: BGIMiniMapLayerDescriptor(
                layerGroupId: nil,
                layerId: "Synthetic",
                name: "Synthetic",
                scale: 1,
                floor: 0,
                top: 1000,
                left: 1000,
                isOverSize: false
            ),
            coarseColorMap: coarse,
            fineGrayMap: fine
        )
    }

    private func makePreparedTemplate(
        rough: PixelImage = PixelImage(width: 52, height: 52, channelCount: 3, values: [Double](repeating: 0, count: 52 * 52 * 3)),
        exact: PixelImage = PixelImage(width: 260, height: 260, channelCount: 1, values: [Double](repeating: 0, count: 260 * 260))
    ) -> BGIMiniMapPreparedTemplate {
        let roughMask = [Double](repeating: 1, count: rough.width * rough.height)
        let exactMask = [Double](repeating: 1, count: exact.width * exact.height)
        return BGIMiniMapPreparedTemplate(
            roughColor: rough,
            roughMask: roughMask,
            exactGray: exact,
            exactMask: exactMask,
            roughWorstSqDiff: worstSqDiff(template: rough, mask: roughMask),
            exactWorstSqDiff: worstSqDiff(template: exact, mask: exactMask)
        )
    }

    private func makePattern(width: Int, height: Int, channels: Int) -> PixelImage {
        var values: [Double] = []
        values.reserveCapacity(width * height * channels)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<channels {
                    values.append(Double((x * 13 + y * 29 + x * y * 3 + channel * 71) % 251 + 2))
                }
            }
        }
        return PixelImage(width: width, height: height, channelCount: channels, values: values)
    }

    private func embed(_ template: PixelImage, inWidth width: Int, height: Int, atX originX: Int, y originY: Int) -> PixelImage {
        var values = [Double](repeating: 1, count: width * height * template.channelCount)
        for y in 0..<template.height {
            for x in 0..<template.width {
                for channel in 0..<template.channelCount {
                    let sourceIndex = ((originY + y) * width + (originX + x)) * template.channelCount + channel
                    values[sourceIndex] = template.value(x: x, y: y, channel: channel)
                }
            }
        }
        return PixelImage(width: width, height: height, channelCount: template.channelCount, values: values)
    }

    private func worstSqDiff(template: PixelImage, mask: [Double]) -> Double {
        var sum = 0.0
        for y in 0..<template.height {
            for x in 0..<template.width {
                for channel in 0..<template.channelCount {
                    let value = template.value(x: x, y: y, channel: channel)
                    let inverted = max(value, 255.0 - value)
                    sum += inverted * inverted * mask[y * template.width + x]
                }
            }
        }
        return sum
    }
}
