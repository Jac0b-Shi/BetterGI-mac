@testable import MacGI
import Foundation
import Testing

@Suite("BetterGI pathing task executor")
struct BGIPathingTaskExecutorTests {
    @Test("pathing task loader decodes upstream snake case JSON and applies monster loot split")
    func decodesUpstreamSnakeCaseJSON() throws {
        let fixture = try PathingFixture()
        let taskURL = try fixture.writePathingTask(
            relativePath: "demo/route.json",
            json: """
            {
              "info": {
                "name": "采集路线",
                "type": "collect",
                "bgi_version": "0.0.1",
                "map_name": "Teyvat",
                "map_match_method": "TemplateMatch",
                "enable_monster_loot_split": true,
                "tags": ["base"]
              },
              "config": {
                "realtime_triggers": { "AutoPick": false }
              },
              "farming_info": {
                "allow_farming_count": true,
                "normal_mob_count": 2,
                "primary_target": "normal"
              },
              "positions": [
                {
                  "x": 12.5,
                  "y": 34.25,
                  "type": "target",
                  "move_mode": "run",
                  "action": "fight",
                  "point_ext_params": { "description": "first" }
                }
              ]
            }
            """
        )

        let task = try BGIPathingTaskExecutor(
            store: fixture.store,
            currentBGIVersion: "1.0.0"
        ).loadTask(from: taskURL)

        #expect(task.fileName == "route.json")
        #expect(task.info.name == "采集路线")
        #expect(task.info.bgiVersion == "0.0.1")
        #expect(task.info.mapMatchMethod == "TemplateMatch")
        #expect(task.config.realtimeTriggers["AutoPick"] == false)
        #expect(task.farmingInfo.allowFarmingCount == true)
        #expect(task.farmingInfo.normalMobCount == 2)
        #expect(task.positions.count == 1)
        #expect(task.positions[0].action == BGIPathingAction.fight)
        #expect(task.positions[0].pointExtParams.description == "first")
        #expect(task.positions[0].pointExtParams.enableMonsterLootSplit == true)
    }

    @Test("control json5 merge mirrors BetterGI global and per-file cover rules")
    func controlJSON5MergeMirrorsBetterGI() throws {
        let fixture = try PathingFixture()
        _ = try fixture.writePathingTask(
            relativePath: "demo/route.json",
            json: """
            {
              "info": {
                "name": "原始路线",
                "type": "collect",
                "tags": ["base"]
              },
              "positions": [
                { "x": 1, "y": 2, "action": "fight" }
              ]
            }
            """
        )
        try fixture.writeControl(
            relativeDirectory: "demo",
            json: """
            {
              // BetterGI names this file control.json5, but parses object content.
              "global_cover": {
                "info": {
                  "_arr_add": ["tags"],
                  "tags": ["global"],
                  "map_name": "Enkanomiya",
                }
              },
              "json_list": [
                {
                  "name": "route",
                  "cover": {
                    "info": { "name": "合并路线" },
                    "config": { "realtime_triggers": { "AutoPick": false } },
                    "positions": [
                      { "x": 9, "y": 10, "action": "pick_around" },
                    ],
                  },
                },
              ],
            }
            """
        )

        let task = try BGIPathingTaskExecutor(store: fixture.store)
            .loadInstalledTask(name: "route.json", folderName: "demo")

        #expect(task.info.name == "合并路线")
        #expect(task.info.mapName == "Enkanomiya")
        #expect(task.info.tags == ["base", "global"])
        #expect(task.config.realtimeTriggers["AutoPick"] == false)
        #expect(task.positions.count == 1)
        #expect(task.positions[0].x == 9)
        #expect(task.positions[0].action == BGIPathingAction.pickAround)
    }

    @Test("installed pathing project supports relative and absolute BetterGI folder names")
    func installedPathingProjectSupportsRelativeAndAbsoluteFolderNames() throws {
        let fixture = try PathingFixture()
        let taskURL = try fixture.writePathingTask(
            relativePath: "demo/route.json",
            json: minimalPathingJSON(name: "可执行路线")
        )
        let executor = BGIPathingTaskExecutor(store: fixture.store)

        let relative = try executor.executeInstalledProject(name: "route.json", folderName: "demo")
        let absolute = try executor.executeInstalledProject(
            name: "route.json",
            folderName: taskURL.deletingLastPathComponent().path
        )

        #expect(relative.status == .loadedAwaitingNavigationBackend)
        #expect(relative.taskName == "可执行路线")
        #expect(relative.waypointCount == 2)
        #expect(relative.actionCounts[BGIPathingAction.fight] == 1)
        #expect(relative.autoPickEnabled == true)
        #expect(absolute.fullPath == relative.fullPath)
    }

    @Test("path executor mirrors BetterGI waypoint segmentation and stage order")
    func pathExecutorMirrorsWaypointSegmentationAndStageOrder() async throws {
        let task = BGIPathingTask(
            info: BGIPathingTaskInfo(name: "执行路线", mapName: "Teyvat", mapMatchMethod: "TemplateMatch"),
            positions: [
                BGIPathingWaypoint(x: 1, y: 2, type: BGIPathingWaypointType.teleport),
                BGIPathingWaypoint(x: 3, y: 4, type: BGIPathingWaypointType.path, action: BGIPathingAction.fight),
                BGIPathingWaypoint(x: 5, y: 6, type: BGIPathingWaypointType.target, action: BGIPathingAction.hydroCollect),
                BGIPathingWaypoint(x: 7, y: 8, type: BGIPathingWaypointType.teleport, action: BGIPathingAction.forceTp),
                BGIPathingWaypoint(x: 9, y: 10, type: BGIPathingWaypointType.orientation),
                BGIPathingWaypoint(x: 11, y: 12, action: BGIPathingAction.upDownGrabLeaf)
            ]
        )
        let backend = RecordingPathingBackend()

        let result = try await BGIPathExecutor(backend: backend).pathing(task)

        #expect(result.successEnd == true)
        #expect(result.successFight == 1)
        #expect(result.segmentCount == 2)
        #expect(result.waypointCount == 6)
        #expect(backend.calls.contains("teleport:false:1.0:2.0"))
        #expect(backend.calls.contains("teleport:true:7.0:8.0"))
        #expect(backend.calls.contains("after:fight"))
        #expect(backend.calls.contains("after:hydro_collect"))
        #expect(backend.calls.contains("face:orientation"))
        #expect(!backend.calls.contains("move:orientation"))
        #expect(backend.calls.contains("before:up_down_grab_leaf"))
        #expect(!backend.calls.contains("move:up_down_grab_leaf"))
        #expect(backend.calls.last == "release")

        let phases = result.events.map(\.phase)
        #expect(phases.first == .switchPartyBefore)
        #expect(phases.contains(.warmUpNavigation))
        #expect(result.events.filter { $0.phase == .segmentBegin }.count == 2)
        #expect(result.events.contains {
            $0.phase == .moveCloseTo && $0.action == BGIPathingAction.hydroCollect
        })
        #expect(!result.events.contains {
            $0.phase == .moveCloseTo && $0.action == BGIPathingAction.fight
        })
    }

    @Test("pathing task executor can run loaded task through navigation backend")
    func taskExecutorRunsLoadedTaskThroughNavigationBackend() async throws {
        let fixture = try PathingFixture()
        _ = try fixture.writePathingTask(
            relativePath: "demo/route.json",
            json: minimalPathingJSON(name: "后端路线")
        )
        let backend = RecordingPathingBackend()

        let result = try await BGIPathingTaskExecutor(store: fixture.store)
            .executeInstalledProject(name: "route.json", folderName: "demo", navigationBackend: backend)

        #expect(result.status == .completedWithNavigationBackend)
        #expect(result.segmentCount == 1)
        #expect(result.successEnd == true)
        #expect(result.successFight == 1)
        #expect(result.actionCounts[BGIPathingAction.fight] == 1)
    }

    @Test("pathing project rejects path traversal and newer BGI version")
    func rejectsTraversalAndFutureBGIVersion() throws {
        let fixture = try PathingFixture()
        let taskURL = try fixture.writePathingTask(
            relativePath: "demo/route.json",
            json: minimalPathingJSON(name: "新版路线", bgiVersion: "9.9.9")
        )
        let executor = BGIPathingTaskExecutor(store: fixture.store, currentBGIVersion: "1.0.0")

        #expect(throws: BGIPathingTaskExecutorError.invalidProjectPath(folderName: "../outside", name: "route.json")) {
            _ = try executor.loadInstalledTask(name: "route.json", folderName: "../outside")
        }
        #expect(throws: BGIPathingTaskExecutorError.unsupportedFutureBGIVersion(required: "9.9.9", current: "1.0.0")) {
            _ = try executor.loadTask(from: taskURL)
        }
    }
}

private final class RecordingPathingBackend: BGIPathingNavigationBackend, @unchecked Sendable {
    var calls: [String] = []

    func switchPartyBefore(task: BGIPathingTask) async throws -> Bool {
        calls.append("switchParty")
        return true
    }

    func validateGameWithTask(task: BGIPathingTask) async throws -> Bool {
        calls.append("validate")
        return true
    }

    func initializePathing(task: BGIPathingTask) async throws {
        calls.append("initialize")
    }

    func warmUpNavigation(mapMatchMethod: String) async throws {
        calls.append("warmUp:\(mapMatchMethod)")
    }

    func setPreviousPosition(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("setPrevious:\(waypoint.gameX):\(waypoint.gameY)")
    }

    func recoverWhenLowHp(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("recover")
    }

    func handleTeleportWaypoint(_ waypoint: BGIPathingWaypointForTrack, force: Bool) async throws {
        calls.append("teleport:\(force):\(waypoint.gameX):\(waypoint.gameY)")
    }

    func beforeMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("before:\(waypoint.action ?? waypoint.type)")
    }

    func faceTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("face:\(waypoint.type)")
    }

    func moveTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("move:\(waypoint.action ?? waypoint.type)")
    }

    func beforeMoveCloseToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("beforeClose:\(waypoint.action ?? waypoint.type)")
    }

    func moveCloseTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("close:\(waypoint.action ?? waypoint.type)")
    }

    func afterMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        calls.append("after:\(waypoint.action ?? "")")
    }

    func releaseAllInputs() async {
        calls.append("release")
    }
}

private struct PathingFixture {
    let rootURL: URL
    let store: BGIRuntimeResourceStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-pathing-test-\(UUID().uuidString)", isDirectory: true)
        store = BGIRuntimeResourceStore(rootURL: rootURL.appendingPathComponent("AppSupport", isDirectory: true))
        try store.createDirectorySkeleton()
    }

    func writePathingTask(relativePath: String, json: String) throws -> URL {
        let url = store.userURL
            .appendingPathComponent("AutoPathing", isDirectory: true)
            .appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.data(using: .utf8)?.write(to: url)
        return url
    }

    func writeControl(relativeDirectory: String, json: String) throws {
        let url = store.userURL
            .appendingPathComponent("AutoPathing", isDirectory: true)
            .appendingPathComponent(relativeDirectory, isDirectory: true)
            .appendingPathComponent("control.json5")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.data(using: .utf8)?.write(to: url)
    }
}

private func minimalPathingJSON(name: String, bgiVersion: String = "0.0.1") -> String {
    """
    {
      "info": {
        "name": "\(name)",
        "type": "collect",
        "bgi_version": "\(bgiVersion)"
      },
      "positions": [
        { "x": 1, "y": 2, "type": "teleport" },
        { "x": 3, "y": 4, "action": "fight" }
      ]
    }
    """
}
