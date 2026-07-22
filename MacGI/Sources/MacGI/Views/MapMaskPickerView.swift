import SwiftUI

struct MapMaskPickerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategoryID: String?
    @State private var searchText = ""

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if appState.isMapMaskPickerOpen {
                picker
                    .padding(.bottom, 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            toggleButton
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .preferredColorScheme(.dark)
    }

    private var toggleButton: some View {
        Button(action: appState.toggleMapMaskPicker) {
            Image(systemName: "globe.asia.australia.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color(red: 0.23, green: 0.26, blue: 0.33))
                .frame(width: 46, height: 46)
                .background(Color(red: 0.93, green: 0.90, blue: 0.85), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 5))
                .shadow(color: .black.opacity(0.28), radius: 3)
        }
        .buttonStyle(.plain)
        .help("地图标点")
    }

    private var picker: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                toolbar
                HStack(alignment: .top, spacing: 10) {
                    categoryList
                        .frame(width: 132)
                    labelGrid
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !selectedLabels.isEmpty {
                selectedLabelStrip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.58), radius: 18)
        .task {
            await appState.ensureMapMaskCatalogLoaded()
            if selectedCategoryID == nil {
                selectedCategoryID = appState.mapMaskLabelCategories.first?.id
            }
        }
        .onChange(of: appState.mapMaskLabelCategories) { _, categories in
            if selectedCategoryID == nil || !categories.contains(where: { $0.id == selectedCategoryID }) {
                selectedCategoryID = categories.first?.id
            }
        }
    }

    private var selectedLabelStrip: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(selectedLabels) { item in
                    Button {
                        appState.setMapMaskLabel(item.id, selected: false)
                    } label: {
                        AsyncImage(url: URL(string: item.iconURL)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                        }
                        .frame(width: 34, height: 34)
                        .padding(4)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("取消显示：\(item.name)")
                }
            }
            .padding(8)
        }
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var toolbar: some View {
        if let settings = appState.mapMaskPickerSettings {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { settings.mapPointApiProvider },
                    set: { appState.saveMapMaskPickerSettings(mapPointApiProvider: $0) })) {
                    ForEach(settings.mapPointApiProviderOptions, id: \.self) { provider in
                        Text(providerName(provider)).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 145)

                if settings.mapPointApiProvider == "HoYoLab" {
                    Picker("", selection: Binding(
                        get: { settings.hoYoLabLanguage },
                        set: { appState.saveMapMaskPickerSettings(hoYoLabLanguage: $0) })) {
                        ForEach(settings.hoYoLabLanguageOptions, id: \.self) { language in
                            Text(languageName(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                TextField("搜索当前区域下的标点分类", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Text("\(appState.mapMaskSelectedLabelIDs.count) 已选")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Button(action: appState.closeMapMaskPicker) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在加载地图标点")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: appState.closeMapMaskPicker) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(appState.mapMaskLabelCategories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        Text(category.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 31)
                            .background(
                                selectedCategoryID == category.id
                                    ? Color.white.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
    }

    private var labelGrid: some View {
        Group {
            if appState.mapMaskCatalogLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLabels.isEmpty {
                Text("当前分类没有匹配的标点")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: 8)], spacing: 8) {
                        ForEach(filteredLabels) { item in
                            labelCard(item)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
    }

    private func labelCard(_ item: BetterGICoreMapMaskLabel) -> some View {
        let selected = appState.mapMaskSelectedLabelIDs.contains(item.id)
        return Button {
            appState.setMapMaskLabel(item.id, selected: !selected)
        } label: {
            HStack(spacing: 7) {
                AsyncImage(url: URL(string: item.iconURL)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                .padding(3)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))

                Text(item.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(item.pointCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(selected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.accentColor.opacity(0.82) : Color.white.opacity(0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var filteredLabels: [BetterGICoreMapMaskLabel] {
        let labels = appState.mapMaskLabelCategories
            .first(where: { $0.id == selectedCategoryID })?.children ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedLabels: [BetterGICoreMapMaskLabel] {
        appState.mapMaskLabelCategories
            .flatMap(\.children)
            .filter { appState.mapMaskSelectedLabelIDs.contains($0.id) }
    }

    private func providerName(_ value: String) -> String {
        switch value {
        case "MihoyoMap": "米游社大地图"
        case "KongyingTavern": "空荧酒馆"
        case "HoYoLab": "HoYoLab"
        default: value
        }
    }

    private func languageName(_ value: String) -> String {
        switch value {
        case "en-us": "English"
        case "pt-pt": "Português"
        case "es-es": "Español"
        default: value
        }
    }
}
