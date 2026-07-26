import AppKit
import SwiftUI

struct MapTrackingPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var expandedDirectories: Set<String> = []
    @State private var selectedEntry: BetterGIPathingEntry?
    @State private var detail: BetterGIPathingDetail?
    @State private var detailError: String?
    @State private var showingRepository = false
    @State private var showingSettings = false
    @State private var deleteCandidate: BetterGIPathingEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                BGIPageTitle(title: "地图追踪（实验功能）")
                Text("可以实现自动采集、自动挖矿、自动锄地等功能。多路线连续执行请使用调度器。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
            }

            commandBar

            HStack(alignment: .top, spacing: 14) {
                catalog
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                detailPanel
                    .frame(width: 320, alignment: .topLeading)
            }
        }
        .task {
            appState.reloadPathingEntriesFromCore()
        }
        .sheet(isPresented: $showingRepository) {
            ScriptRepositorySheet()
        }
        .sheet(isPresented: $showingSettings) {
            PathingSettingsSheet()
                .environmentObject(appState)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } })
        ) {
            Button("删除", role: .destructive) {
                guard let candidate = deleteCandidate else { return }
                appState.deletePathingEntry(id: candidate.id)
                if selectedEntry?.id == candidate.id {
                    selectedEntry = nil
                    detail = nil
                }
                deleteCandidate = nil
            }
            Button("取消", role: .cancel) {
                deleteCandidate = nil
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Button {
                appState.openPathingRootLocation()
            } label: {
                Label("打开任务目录", systemImage: "folder")
            }
            Button {
                showingRepository = true
            } label: {
                Label("脚本仓库", systemImage: "archivebox")
            }
            Button {
                showingSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            Button {
                guard let url = URL(string: "https://www.bettergi.com/feats/autos/pathing.html")
                else { return }
                NSWorkspace.shared.open(url)
            } label: {
                Label("使用教程", systemImage: "questionmark.circle")
            }
            Spacer()
            Button {
                appState.reloadPathingEntriesFromCore()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
    }

    private var catalog: some View {
        BGISectionCard(
            "路径任务",
            subtitle: appState.pathingCatalogStatus,
            symbolName: "map"
        ) {
            TextField("搜索路线或目录", text: $searchText)
                .textFieldStyle(.roundedBorder)

            LazyVStack(spacing: 0) {
                ForEach(visibleEntries) { entry in
                    pathingRow(entry)
                    Divider()
                }
                if visibleEntries.isEmpty {
                    Text(searchText.isEmpty ? "任务目录中没有地图追踪路线。" : "没有匹配的路线。")
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.mutedText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                }
            }
        }
    }

    private func pathingRow(_ entry: BetterGIPathingEntry) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(depth(of: entry)) * 16)
            if entry.isDirectory {
                Button {
                    toggleDirectory(entry.id)
                } label: {
                    Image(systemName: expandedDirectories.contains(entry.id)
                          ? "chevron.down" : "chevron.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(BGIColors.mutedText)
                    .frame(width: 16, height: 16)
            }

            Button {
                select(entry)
            } label: {
                HStack(spacing: 7) {
                    if entry.isDirectory {
                        Image(systemName: "folder")
                            .foregroundStyle(BGIColors.warning)
                    }
                    Text(entry.name)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !entry.isDirectory {
                Button {
                    appState.runPathingEntry(id: entry.id)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("执行任务")
                .disabled(appState.currentSchedulerProjectID != nil)
            }

            Menu {
                if !entry.isDirectory {
                    Button("执行任务") {
                        appState.runPathingEntry(id: entry.id)
                    }
                    .disabled(appState.currentSchedulerProjectID != nil)
                }
                Button("删除", role: .destructive) {
                    deleteCandidate = entry
                }
                .disabled(appState.currentSchedulerProjectID != nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(selectedEntry?.id == entry.id ? BGIColors.cardElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small))
    }

    private var detailPanel: some View {
        BGISectionCard(
            selectedEntry?.name ?? "任务详情",
            subtitle: selectedEntry?.id,
            symbolName: selectedEntry?.isDirectory == true ? "folder" : "doc.text"
        ) {
            if let detail {
                VStack(alignment: .leading, spacing: 10) {
                    if let author = detail.author, !author.isEmpty {
                        detailLine("作者", author)
                    }
                    if let version = detail.version, !version.isEmpty {
                        detailLine("版本", version)
                    }
                    if !detail.mapName.isEmpty {
                        detailLine("地图", detail.mapName)
                    }
                    if detail.type != "Directory" {
                        detailLine("路径点", "\(detail.waypointCount)")
                    }
                    if !detail.tags.isEmpty {
                        detailLine("标签", detail.tags.joined(separator: "、"))
                    }
                    if let description = detail.description, !description.isEmpty {
                        Divider()
                        Text(description)
                            .font(BGIFonts.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let readme = detail.readme, !readme.isEmpty {
                        Divider()
                        Text(.init(readme))
                            .font(BGIFonts.body)
                            .textSelection(.enabled)
                    }
                }
            } else if let detailError {
                Text(detailError)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.danger)
                    .textSelection(.enabled)
            } else if selectedEntry != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                Text("选择目录或路线查看详情。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.mutedText)
            }
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(BGIColors.mutedText)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(BGIFonts.body)
    }

    private var visibleEntries: [BetterGIPathingEntry] {
        let entries = appState.pathingEntries
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            return entries.filter { entry in
                var parentID = entry.parentID
                while let id = parentID {
                    guard expandedDirectories.contains(id) else { return false }
                    parentID = byID[id]?.parentID
                }
                return true
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var included = Set(
            entries.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }.map(\.id))
        for id in included {
            var parentID = byID[id]?.parentID
            while let parent = parentID {
                included.insert(parent)
                parentID = byID[parent]?.parentID
            }
        }
        return entries.filter { included.contains($0.id) }
    }

    private func depth(of entry: BetterGIPathingEntry) -> Int {
        max(0, entry.id.split(separator: "/").count - 1)
    }

    private func toggleDirectory(_ id: String) {
        if expandedDirectories.contains(id) {
            expandedDirectories.remove(id)
        } else {
            expandedDirectories.insert(id)
        }
    }

    private func select(_ entry: BetterGIPathingEntry) {
        selectedEntry = entry
        detail = nil
        detailError = nil
        if entry.isDirectory {
            toggleDirectory(entry.id)
        }
        Task {
            do {
                let loaded = try await appState.loadPathingDetail(id: entry.id)
                guard selectedEntry?.id == entry.id else { return }
                detail = loaded
            } catch {
                guard selectedEntry?.id == entry.id else { return }
                detailError = error.localizedDescription
            }
        }
    }

    private var deleteTitle: String {
        guard let candidate = deleteCandidate else { return "删除地图追踪项目？" }
        let type = candidate.isDirectory ? "文件夹及其中全部内容" : "路线"
        return "确定删除\(type)“\(candidate.name)”？此操作无法恢复。"
    }
}

private struct PathingSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var settings: BetterGIPathingSettings?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("地图追踪设置")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()
            Divider()

            if let settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        conditionGroup(
                            title: "队伍切换设置",
                            subtitle: "路径中存在符合条件的动作、采集物时，自动切换至对应队伍。",
                            conditions: Binding(
                                get: { settings.partyConditions },
                                set: { self.settings?.partyConditions = $0 }),
                            subjects: settings.partySubjects,
                            freeformResult: true)
                        conditionGroup(
                            title: "角色设置",
                            subtitle: "存在多个符合条件的角色时，优先使用游戏内编队编号更小的角色。",
                            conditions: Binding(
                                get: { settings.avatarConditions },
                                set: { self.settings?.avatarConditions = $0 }),
                            subjects: settings.avatarSubjects,
                            freeformResult: false)

                        BGISettingLine(
                            title: "使用小道具的间隔时间（毫秒）",
                            subtitle: "在移动期间自动使用小道具，填 0 为不使用。"
                        ) {
                            TextField(
                                "",
                                value: Binding(
                                    get: { settings.useGadgetIntervalMs },
                                    set: { self.settings?.useGadgetIntervalMs = $0 }),
                                format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                        }
                        BGISettingLine(
                            title: "开启自动吃药",
                            subtitle: "检测到红血状态时自动使用便携营养袋。"
                        ) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { settings.autoEatEnabled },
                                    set: { self.settings?.autoEatEnabled = $0 }))
                                .labelsHidden()
                        }
                        BGISettingLine(
                            title: "低血量回复时机",
                            subtitle: "选择任何路径点、只在传送点或不回复。"
                        ) {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { settings.recoverTiming },
                                    set: { self.settings?.recoverTiming = $0 })
                            ) {
                                Text("任何路径点").tag("AnyWaypoint")
                                Text("只在传送点").tag("OnlyTeleport")
                                Text("不回复").tag("Never")
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }
                    .padding()
                }
            } else if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error)
                        .foregroundStyle(BGIColors.danger)
                        .textSelection(.enabled)
                    Button("重试") {
                        Task { await load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                if let error, settings != nil {
                    Text(error)
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings == nil || saving)
            }
            .padding()
        }
        .frame(width: 860, height: 720)
        .task {
            await load()
        }
    }

    private func conditionGroup(
        title: String,
        subtitle: String,
        conditions: Binding<[BetterGIPathingCondition]>,
        subjects: [String],
        freeformResult: Bool
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(conditions.wrappedValue.indices, id: \.self) { index in
                    PathingConditionRow(
                        condition: Binding(
                            get: { conditions.wrappedValue[index] },
                            set: { conditions.wrappedValue[index] = $0 }),
                        definitions: settings?.definitions ?? [:],
                        subjects: subjects,
                        freeformResult: freeformResult,
                        remove: {
                            conditions.wrappedValue.remove(at: index)
                        })
                    if index != conditions.wrappedValue.indices.last {
                        Divider()
                    }
                }
                Button {
                    guard let subject = subjects.first else { return }
                    let definition = settings?.definitions[subject]
                    conditions.wrappedValue.append(BetterGIPathingCondition(
                        subject: subject,
                        predicate: definition?.predicates.first ?? "包含",
                        result: freeformResult ? "" : definition?.results.first ?? ""))
                } label: {
                    Label("添加条件", systemImage: "plus")
                }
            }
            .padding(8)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle)
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.secondaryText)
            }
        }
    }

    private func load() async {
        error = nil
        do {
            settings = try await appState.loadPathingSettings()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        guard let settings else { return }
        saving = true
        error = nil
        Task {
            do {
                self.settings = try await appState.savePathingSettings(settings)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

private struct PathingConditionRow: View {
    @Binding var condition: BetterGIPathingCondition
    let definitions: [String: BetterGIPathingConditionDefinition]
    let subjects: [String]
    let freeformResult: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Picker("", selection: subjectBinding) {
                    ForEach(subjects, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Picker("", selection: $condition.predicate) {
                    ForEach(definition?.predicates ?? ["包含"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 90)

                TextField("选项使用顿号分隔", text: objectsBinding)
                    .textFieldStyle(.roundedBorder)

                if freeformResult {
                    TextField("队伍名称", text: $condition.result)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                } else {
                    Picker("", selection: $condition.result) {
                        ForEach(definition?.results ?? [], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            if let description = definition?.description, !description.isEmpty {
                Text(description)
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let objects = definition?.objects, !objects.isEmpty {
                Menu {
                    ForEach(objects, id: \.self) { object in
                        Button {
                            if condition.objects.contains(object) {
                                condition.objects.removeAll { $0 == object }
                            } else {
                                condition.objects.append(object)
                            }
                        } label: {
                            Label(
                                object,
                                systemImage: condition.objects.contains(object)
                                    ? "checkmark" : "plus")
                        }
                    }
                } label: {
                    Label("从支持列表选择（\(condition.objects.count)）", systemImage: "list.bullet")
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var definition: BetterGIPathingConditionDefinition? {
        definitions[condition.subject]
    }

    private var subjectBinding: Binding<String> {
        Binding(
            get: { condition.subject },
            set: { subject in
                condition.subject = subject
                condition.objects = []
                let next = definitions[subject]
                condition.predicate = next?.predicates.first ?? "包含"
                if !freeformResult {
                    condition.result = next?.results.first ?? ""
                }
            })
    }

    private var objectsBinding: Binding<String> {
        Binding(
            get: { condition.objects.joined(separator: "、") },
            set: { text in
                condition.objects = text
                    .components(separatedBy: CharacterSet(charactersIn: "、,，\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            })
    }
}
