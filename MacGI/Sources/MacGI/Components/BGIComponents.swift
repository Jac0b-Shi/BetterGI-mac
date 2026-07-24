import AppKit
import SwiftUI

struct BGIBundledImage: View {
    let resource: String
    let fileExtension: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let url = Bundle.macGIResources.url(forResource: resource, withExtension: fileExtension, subdirectory: "Images")
            ?? Bundle.macGIResources.url(forResource: resource, withExtension: fileExtension),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Rectangle()
                .fill(BGIColors.cardElevated)
        }
    }
}

enum BGIIcon: Equatable {
    case symbol(String)
    case fgi(String)
}

struct BGIIconView: View {
    let icon: BGIIcon
    var size: CGFloat = 21

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .frame(width: 30, height: 30)
        case .fgi(let glyph):
            Text(glyph)
                .font(.custom("FgiRegular", size: size))
                .frame(width: 30, height: 30)
        }
    }
}

struct BGISectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbolName: String?
    @ViewBuilder var content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbolName: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.medium) {
            HStack(alignment: .top, spacing: BGISpacing.medium) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BGIColors.accent)
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BGIFonts.sectionTitle)
                        .foregroundStyle(BGIColors.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(BGIFonts.body)
                            .foregroundStyle(BGIColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(BGISpacing.large)
        .bgiCard()
    }
}

struct BGIStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(BGIFonts.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

struct BGIPageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(BGIColors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BGISettingGroup<HeaderAction: View, Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var headerAction: HeaderAction
    @ViewBuilder var content: Content
    private let expandedBinding: Binding<Bool>?
    @State private var localExpanded: Bool

    init(
        icon: String,
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>? = nil,
        initiallyExpanded: Bool = true,
        @ViewBuilder headerAction: () -> HeaderAction,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        expandedBinding = isExpanded
        _localExpanded = State(initialValue: initiallyExpanded)
        self.headerAction = headerAction()
        self.content = content()
    }

    private var isExpanded: Bool {
        expandedBinding?.wrappedValue ?? localExpanded
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: BGISpacing.large) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(BGIColors.primaryText.opacity(0.84))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BGIColors.primaryText)
                    Text(subtitle)
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 20)
                headerAction
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BGIColors.secondaryText)
                    .frame(width: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if let expandedBinding {
                        expandedBinding.wrappedValue.toggle()
                    } else {
                        localExpanded.toggle()
                    }
                }
            }

            if isExpanded && !(Content.self == EmptyView.self) {
                Divider().overlay(BGIColors.border)
                content
            }
        }
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGISettingLine<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var control: Control

    init(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: BGISpacing.large) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BGIFonts.bodyStrong)
                    .foregroundStyle(BGIColors.primaryText)
                Text(subtitle)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 20)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(minHeight: 72)
        .overlay(Rectangle().fill(BGIColors.border).frame(height: 1), alignment: .top)
    }
}

struct BGITaskCard<Trailing: View>: View {
    let icon: BGIIcon
    let title: String
    let subtitle: String
    let indent: CGFloat
    @ViewBuilder var trailing: Trailing

    init(
        icon: BGIIcon,
        title: String,
        subtitle: String,
        indent: CGFloat = 0,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.indent = indent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: BGISpacing.large) {
            BGIIconView(icon: icon, size: 21)
                .foregroundStyle(BGIColors.primaryText.opacity(0.82))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BGIColors.primaryText)
                Text(subtitle)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 20)
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 74)
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
        .padding(.leading, indent)
    }
}

struct BGIExpandableTaskCard<Trailing: View, Content: View>: View {
    let icon: BGIIcon
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: BGISpacing.large) {
                BGIIconView(icon: icon, size: 21)
                    .foregroundStyle(BGIColors.primaryText.opacity(0.82))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BGIColors.primaryText)
                    Text(subtitle)
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 20)
                trailing
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BGIColors.secondaryText)
                    .frame(width: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: 74)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider().overlay(BGIColors.border)
                content
            }
        }
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGIFeatureToggle: View {
    let feature: MacGIFeature
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: BGISpacing.medium) {
            BGIIconView(icon: feature.icon, size: 18)
                .foregroundStyle(isOn ? BGIColors.success : BGIColors.muted)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(feature.name)
                        .font(BGIFonts.bodyStrong)
                        .foregroundStyle(BGIColors.primaryText)
                    BGIStatusBadge(text: feature.statusText, tint: isOn ? BGIColors.success : BGIColors.muted)
                }
                Text(feature.detail)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(BGISpacing.medium)
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGILogConsole: View {
    let entries: [LogEntry]
    var compact = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: compact ? 3 : 6) {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("[\(entry.timeText) \(entry.level.label)]")
                            .foregroundStyle(entry.level.tint)
                        Text(entry.message)
                            .foregroundStyle(BGIColors.primaryText.opacity(0.9))
                        Spacer(minLength: 0)
                    }
                    .font(BGIFonts.console)
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 8 : 12)
        }
        .background(BGIColors.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGIHeaderBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            BGIBundledImage(resource: "bettergi-logo", fileExtension: "png")
                .frame(width: 22, height: 22)
                .clipShape(Circle())
            Text("betterGI-mac · 更好的原神 · Swift Prototype")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BGIColors.primaryText)
            Spacer()
            Button {
                appState.addTestLog()
            } label: {
                Image(systemName: "gift")
            }
            .buttonStyle(.plain)
            .foregroundStyle(BGIColors.accent)
            BGIStatusBadge(text: appState.appStatus.label, tint: appState.appStatus.tint)
            Button {
                appState.toggleRuntime()
            } label: {
                Image(systemName: appState.runtimeLifecycle == .running ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(BGIColors.secondaryText)
            .disabled(appState.runtimeLifecycle.isTransitioning)
        }
        .frame(height: 54)
        .padding(.horizontal, 20)
        .background(BGIColors.sidebarBackground)
        .overlay(Rectangle().fill(BGIColors.border).frame(height: 1), alignment: .bottom)
    }
}

struct BGINavSidebar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BGIColors.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            sidebarButton(.launch)
            sidebarButton(.realtime)
            sidebarButton(.soloTask)
            sidebarButton(.oneDragon)
            automationHeader
            sidebarButton(.scheduler, indent: 28)
            sidebarButton(.jsScript, indent: 28)
            sidebarButton(.mapTracking, indent: 28)
            sidebarButton(.recordReplay, indent: 28)
            sidebarButton(.macro)
            sidebarButton(.hotkey)
            sidebarButton(.notification)

            Spacer()

            sidebarButton(.settings)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 184, idealWidth: 184, maxWidth: 184)
        .background(BGIColors.sidebarBackground)
        .overlay(Rectangle().fill(BGIColors.border).frame(width: 1), alignment: .trailing)
    }

    private var automationHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
            Text("全自动")
                .font(BGIFonts.bodyStrong)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(BGIColors.secondaryText)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
    }

    private func sidebarButton(_ page: NavigationPage, indent: CGFloat = 0) -> some View {
        Button {
            appState.selectedPage = page
        } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(appState.selectedPage == page ? BGIColors.accent : Color.clear)
                    .frame(width: 3)
                    .clipShape(Capsule())
                Image(systemName: page.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                Text(page.title)
                    .font(BGIFonts.bodyStrong)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(appState.selectedPage == page ? BGIColors.primaryText : BGIColors.secondaryText)
            .padding(.leading, 4 + indent)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .background(appState.selectedPage == page ? BGIColors.cardElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

struct StatusMetricCard: View {
    let metric: RuntimeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(BGIFonts.caption)
                .foregroundStyle(BGIColors.secondaryText)
            HStack {
                Text(metric.value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BGIColors.primaryText)
                Spacer()
                Circle()
                    .fill(metric.status.tint)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(BGISpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: BGISpacing.large) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BGIFonts.bodyStrong)
                    .foregroundStyle(BGIColors.primaryText)
                Text(detail)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 5)
    }
}
