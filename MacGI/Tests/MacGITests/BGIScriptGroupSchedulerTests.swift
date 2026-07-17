@testable import MacGI
import Foundation
import Testing

@Suite("BetterGI script group scheduler")
struct BGIScriptGroupSchedulerTests {
    @Test("script group project JSON keeps BetterGI ConfigService camelCase keys")
    func scriptGroupProjectJSONKeepsConfigServiceCamelCaseKeys() throws {
        let project = BGIScriptGroupProject.javascript(
            index: 7,
            name: "领取每日奖励",
            folderName: "daily",
            runNum: 2,
            settingsJSON: #"{"mode":"daily"}"#
        )

        let data = try JSONEncoder().encode(project)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["name"] as? String == "领取每日奖励")
        #expect(object["folderName"] as? String == "daily")
        #expect(object["type"] as? String == "Javascript")
        #expect(object["status"] as? String == "Enabled")
        #expect(object["schedule"] as? String == "Daily")
        #expect(object["runNum"] as? Int == 2)
        #expect((object["jsScriptSettingsObject"] as? [String: Any])?["mode"] as? String == "daily")
        #expect(object["jsScriptSettingsJSON"] == nil)
        #expect(object["Name"] == nil)
        #expect(object["FolderName"] == nil)
    }

    @Test("script group project decodes upstream JS settings object")
    func scriptGroupProjectDecodesUpstreamJSSettingsObject() throws {
        let data = Data("""
        {
          "index": 2,
          "name": "锄地一条龙",
          "folderName": "AutoHoeingOneDragon",
          "type": "Javascript",
          "status": "Enabled",
          "schedule": "Daily",
          "runNum": 1,
          "jsScriptSettingsObject": {
            "accountName": "默认账户",
            "skipCheck": true,
            "targetMonsters": "愚人众特辖队，巡陆艇"
          }
        }
        """.utf8)

        let project = try JSONDecoder().decode(BGIScriptGroupProject.self, from: data)
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(project.jsScriptSettingsJSON.utf8)) as? [String: Any]
        )

        #expect(project.folderName == "AutoHoeingOneDragon")
        #expect(settings["accountName"] as? String == "默认账户")
        #expect(settings["skipCheck"] as? Bool == true)
        #expect(settings["targetMonsters"] as? String == "愚人众特辖队，巡陆艇")
    }

    @Test("real dog food hoeing script group decodes when present")
    func realDogFoodHoeingScriptGroupDecodesWhenPresent() throws {
        let store = BGIRuntimeResourceStore.defaultStore()
        let groupURL = store.userURL
            .appendingPathComponent("ScriptGroup", isDirectory: true)
            .appendingPathComponent("狗粮+锄地.json")
        guard FileManager.default.fileExists(atPath: groupURL.path) else {
            return
        }

        let group = try JSONDecoder().decode(BGIScriptGroup.self, from: Data(contentsOf: groupURL))

        #expect(group.name == "狗粮+锄地")
        #expect(group.projects.map(\.folderName).contains("WeeklyThousandStarRealm"))
        #expect(group.projects.map(\.folderName).contains("AutoHoeingOneDragon"))
        #expect(group.projects.map(\.folderName).contains("AAA-Artifacts-Bulk-Supply"))
        #expect(group.projects.allSatisfy { $0.type == .javascript })

        let hoeing = try #require(group.projects.first { $0.folderName == "AutoHoeingOneDragon" })
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(hoeing.jsScriptSettingsJSON.utf8)) as? [String: Any]
        )
        #expect(settings["accountName"] as? String == "默认账户")
        #expect(settings["operationMode"] as? String == "启用仅指定怪物模式")
        #expect(settings["targetMonsters"] as? String == "愚人众特辖队，巡陆艇")
    }

    @Test("script group config decodes missing upstream fields with BetterGI defaults")
    func scriptGroupConfigDecodesMissingFieldsWithDefaults() throws {
        let data = #"{"index":2,"name":"旧配置组","projects":[]}"#.data(using: .utf8)!

        let group = try JSONDecoder().decode(BGIScriptGroup.self, from: data)

        #expect(group.index == 2)
        #expect(group.name == "旧配置组")
        #expect(group.config.enableShellConfig == false)
        #expect(group.config.shellConfig.timeout == 60)
        #expect(group.config.shellConfig.noWindow == true)
        #expect(group.config.shellConfig.output == true)
    }

    @Test("script group shell config keeps upstream camelCase keys")
    func scriptGroupShellConfigKeepsUpstreamCamelCaseKeys() throws {
        let group = BGIScriptGroup(
            index: 1,
            name: "带 Shell 配置",
            config: BGIScriptGroupConfig(
                shellConfig: BGIShellConfig(disable: true, timeout: 3, noWindow: false, output: false),
                enableShellConfig: true
            ),
            projects: [
                BGIScriptGroupProject(index: 1, name: "echo ok", folderName: "", type: .shell)
            ]
        )

        let data = try JSONEncoder().encode(group)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try #require(object["config"] as? [String: Any])
        let shellConfig = try #require(config["shellConfig"] as? [String: Any])

        #expect(config["enableShellConfig"] as? Bool == true)
        #expect(shellConfig["disable"] as? Bool == true)
        #expect(shellConfig["timeout"] as? Int == 3)
        #expect(shellConfig["noWindow"] as? Bool == false)
        #expect(shellConfig["output"] as? Bool == false)
        #expect(config["EnableShellConfig"] == nil)
        #expect(config["ShellConfig"] == nil)
    }

    @Test("nextGroups starts from upstream NextFlag group and clears it")
    func nextGroupsStartsFromNextFlagGroup() {
        let groups = [
            BGIScriptGroup(index: 0, name: "A", projects: []),
            BGIScriptGroup(index: 1, name: "B", projects: [], nextFlag: true),
            BGIScriptGroup(index: 2, name: "C", projects: [])
        ]

        let selected = BGIScriptGroupScheduler.nextGroups(groups)

        #expect(selected.map(\.name) == ["B", "C"])
        #expect(selected.first?.nextFlag == false)
    }

    @Test("nextProjects preserves order and marks projects before NextFlag as skipped")
    func nextProjectsPreservesSkippedPrefix() {
        let group = BGIScriptGroup(
            name: "默认配置组",
            projects: [
                .javascript(index: 1, name: "领取每日奖励", folderName: "daily"),
                .javascript(index: 2, name: "清体力秘境", folderName: "domain", nextFlag: true),
                BGIScriptGroupProject(index: 3, name: "截图归档", folderName: "", type: .shell)
            ]
        )

        let projects = BGIScriptGroupScheduler.nextProjects(in: group)

        #expect(projects.map(\.name) == ["领取每日奖励", "清体力秘境", "截图归档"])
        #expect(projects[0].skipFlag == true)
        #expect(projects[1].skipFlag != true)
        #expect(projects[2].skipFlag != true)
    }

    @Test("executableRuns skips disabled and SkipFlag projects and expands RunNum")
    func executableRunsMirrorsRunMultiFirstLayerFiltering() {
        let projects: [BGIScriptGroupProject] = [
            .javascript(index: 1, name: "跳过", folderName: "skip", skipFlag: true),
            .javascript(index: 2, name: "禁用", folderName: "disabled", status: .disabled),
            .javascript(index: 3, name: "重复", folderName: "repeat", runNum: 3)
        ]

        let runs = BGIScriptGroupScheduler.executableRuns(from: projects)

        #expect(runs.map(\.folderName) == ["repeat", "repeat", "repeat"])
    }
}
