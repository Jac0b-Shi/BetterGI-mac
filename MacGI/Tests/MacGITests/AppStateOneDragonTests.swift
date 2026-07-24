import Foundation
@testable import MacGI
import Testing

@Suite("AppState one-dragon document")
struct AppStateOneDragonTests {
    @MainActor
    @Test("Removing a task preserves unknown config and clears its resume marker")
    func removingTaskPreservesUnknownConfig() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bettergi-one-dragon-document-\(UUID().uuidString)",
                isDirectory: true)
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(rootURL: root))
        appState.oneDragonDocument = BetterGIOneDragonConfigDocument(
            name: "每日",
            config: [
                "Name": .string("每日"),
                "NextTaskId": .string("task-1"),
                "TaskDefinitions": .object([
                    "task-1": .string("领取邮件"),
                    "task-2": .string("自动秘境"),
                    "task-3": .string("锄地"),
                ]),
                "TaskEnabledList": .object([
                    "task-1": .bool(true),
                    "task-2": .bool(false),
                    "task-3": .bool(true),
                ]),
                "TaskOrder": .strings(["task-1", "task-2", "task-3"]),
                "FutureUpstreamSetting": .object([
                    "mode": .string("future"),
                ]),
            ],
            tasks: [
                .init(
                    id: "task-1",
                    name: "领取邮件",
                    isEnabled: true,
                    isResumeStep: true),
                .init(
                    id: "task-2",
                    name: "自动秘境",
                    isEnabled: false,
                    isResumeStep: false),
                .init(
                    id: "task-3",
                    name: "锄地",
                    isEnabled: true,
                    isResumeStep: false),
            ],
            builtInTaskNames: ["领取邮件", "自动秘境"])

        appState.removeOneDragonTask(id: "task-1")
        appState.addOneDragonTask("领取邮件")

        #expect(
            appState.oneDragonDocument?.tasks.map(\.name)
                == ["自动秘境", "领取邮件", "锄地"])
        #expect(appState.oneDragonStringValue("NextTaskId") == "")
        #expect(appState.oneDragonStringsValue("TaskOrder").last == "task-3")
        #expect(
            appState.oneDragonDocument?.config["FutureUpstreamSetting"]
                == .object(["mode": .string("future")]))
    }
}
