import Foundation

/// 上游 `GiTpPosition` 的 Swift 镜像，表示一个传送点（神像/锚点/秘境等）。
struct BGIGameTeleportPoint: Codable, Equatable, Sendable {
    let id: Int
    let type: String
    let name: String?
    let country: String?
    let areas: [String]?
    let x: Double
    let y: Double

    enum CodingKeys: String, CodingKey {
        case id, type, name, country, areas, position, tranPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        areas = try container.decodeIfPresent([String].self, forKey: .areas)

        if let tp = try? container.decode([Double].self, forKey: .tranPosition), tp.count >= 2 {
            x = tp[0]
            y = tp[1]
        } else if let pos = try? container.decode([Double].self, forKey: .position), pos.count >= 2 {
            x = pos[0]
            y = pos[1]
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.tranPosition],
                    debugDescription: "传送点 id=\(id) 缺少坐标 (tranPosition 和 position 均缺失)"
                )
            )
        }
        // Validate: coordinates must be finite numbers, not NaN or infinite
        guard x.isFinite, y.isFinite else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "传送点 id=\(id) 坐标无效 (\(x), \(y))"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(areas, forKey: .areas)
        try container.encode([x, y, 0], forKey: .tranPosition)
    }

    var isGoddess: Bool { type == "Goddess" }
}

/// 上游 `GiWorldScene` 的 Swift 镜像，包含一个场景的所有传送点。
struct BGIWorldScene: Codable, Sendable {
    let mapName: String
    let sceneId: Int
    let description: String?
    let points: [BGIGameTeleportPoint]

    enum CodingKeys: String, CodingKey {
        case mapName, sceneId, description, points
    }
}

/// 上游 `tp.json` 的根结构。
struct BGITeleportDataRoot: Decodable {
    let data: [BGIWorldScene]
}

// MARK: - Loader

struct BGIWorldSceneAssets {
    private static let shared = BGIWorldSceneAssets()

    private let scenesByMap: [String: BGIWorldScene]

    init() {
        guard let url = Bundle.module.url(
            forResource: "tp",
            withExtension: "json",
            subdirectory: "Resources/GameTask/AutoTrackPath/Assets"
        ) else {
            preconditionFailure("tp.json not found in bundle — teleport data is required")
        }
        do {
            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(BGITeleportDataRoot.self, from: data)
            guard !root.data.isEmpty else {
                preconditionFailure("tp.json decoded with empty data array")
            }
            var dict = [String: BGIWorldScene]()
            for scene in root.data {
                guard !scene.mapName.isEmpty else { continue }
                dict[scene.mapName] = scene
            }
            if dict.isEmpty {
                preconditionFailure("tp.json loaded but no valid scenes found")
            }
            scenesByMap = dict
        } catch {
            preconditionFailure("tp.json load failed: \(error.localizedDescription)")
        }
    }

    static func scene(for mapName: String) -> BGIWorldScene? {
        shared.scenesByMap[mapName]
    }

    /// 上游 `GetNearestNTpPoints`: 按距离排序，取最近的 n 个传送点。
    static func nearestTeleportPoints(
        toX x: Double,
        y: Double,
        mapName: String = "Teyvat",
        n: Int = 1
    ) -> [BGIGameTeleportPoint] {
        guard let scene = scene(for: mapName) else { return [] }
        return scene.points
            .sorted { p1, p2 in
                let d1 = pow(p1.x - x, 2) + pow(p1.y - y, 2)
                let d2 = pow(p2.x - x, 2) + pow(p2.y - y, 2)
                return d1 < d2
            }
            .prefix(max(1, n))
            .map { $0 }
    }

    /// 上游 `GetNearestGoddess`: 从神像位置中找最近的一个。
    static func nearestGoddess(
        toX x: Double,
        y: Double,
        mapName: String = "Teyvat"
    ) -> BGIGameTeleportPoint? {
        guard let scene = scene(for: mapName) else { return nil }
        return scene.points
            .filter(\.isGoddess)
            .min { p1, p2 in
                let d1 = pow(p1.x - x, 2) + pow(p1.y - y, 2)
                let d2 = pow(p2.x - x, 2) + pow(p2.y - y, 2)
                return d1 < d2
            }
    }

    /// 上游国家中心位置 (MapLazyAssets.CountryPositions)。
    static let countryPositions: [String: (x: Double, y: Double)] = [
        "蒙德": (-876, 2278),
        "璃月": (270, -666),
        "稻妻": (-4400, -3050),
        "须弥": (2877, -374),
        "枫丹": (4515, 3631),
        "纳塔": (8973.5, -1879.1),
        "挪德卡莱": (9542.25, 1661.84),
    ]

    /// Returns the country name whose center is closest to (x, y), or nil if
    /// the closest distance exceeds a threshold (target is not in Teyvat).
    static func closestCountry(toX x: Double, y: Double) -> String? {
        var minName: String?
        var minDist = Double.greatestFiniteMagnitude
        for (name, pos) in countryPositions {
            let d = sqrt(pow(pos.x - x, 2) + pow(pos.y - y, 2))
            if d < minDist { minDist = d; minName = name }
        }
        return minName
    }
}
