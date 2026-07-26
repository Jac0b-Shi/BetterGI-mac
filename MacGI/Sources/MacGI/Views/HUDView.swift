import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Color.clear

                if appState.showOverlayBorder {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(BGIColors.accent.opacity(0.55), lineWidth: 1)
                        .padding(1)
                }

                CoreOverlayHUDLayer(
                    store: appState.coreOverlayStore,
                    size: size,
                    capturePixelSize: appState.selectedWindow.capturePixelSize,
                    opacity: appState.hudOpacity,
                    showMapPoints: appState.showOverlayMapPoints,
                    showRecognition: appState.showOverlayRecognition,
                    skillCdSettings: appState.skillCdTriggerSettings)

                if appState.showOverlayDirections {
                    directionMarkers(size: size)
                }

                if appState.showOverlayMetrics {
                    metricsOverlay
                        .frame(width: max(360, size.width * 477 / 1920), height: max(58, size.height * 58 / 1080), alignment: .topLeading)
                        .position(x: 20 + max(360, size.width * 477 / 1920) / 2, y: size.height * 744 / 1080 + max(58, size.height * 58 / 1080) / 2)
                }

                if appState.showOverlayStatus {
                    statusOverlay
                        .frame(width: max(360, size.width * 480 / 1920), height: 28, alignment: .leading)
                        .position(x: 20 + max(360, size.width * 480 / 1920) / 2, y: size.height * 790 / 1080 + 14)
                }

                if appState.showOverlayLogBox {
                    logOverlay
                        .frame(width: max(420, size.width * 480 / 1920), height: max(132, size.height * 188 / 1080), alignment: .topLeading)
                        .position(x: 20 + max(420, size.width * 480 / 1920) / 2, y: size.height * 822 / 1080 + max(132, size.height * 188 / 1080) / 2)
                }

                if appState.overlayUidCoverEnabled {
                    uidCover(size: size)
                }

                if appState.overlayLayoutEditEnabled {
                    editModeOverlay
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var statusOverlay: some View {
        HStack(spacing: 8) {
            ForEach(appState.overlayStatusItems) { item in
                HStack(spacing: 3) {
                    Text(item.glyph)
                        .font(.custom("FgiRegular", size: 12))
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                }
                .foregroundStyle(item.isEnabled ? Color(red: 0.58, green: 1.0, blue: 0.58).opacity(appState.hudOpacity) : Color.lightGray.opacity(appState.hudOpacity))
            }
            Spacer(minLength: 0)
        }
        .shadow(color: .black.opacity(0.7), radius: 4)
        .allowsHitTesting(false)
    }

    private var logOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(appState.recentLogs.prefix(appState.hudMaxLogLines))) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text("[\(entry.timeText) \(entry.level.label)]")
                        .foregroundStyle(entry.level.tint)
                        .fixedSize()
                    Text(entry.message)
                        .foregroundStyle(Color.lightGray.opacity(appState.hudOpacity))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 5)
        .shadow(color: .black.opacity(0.7), radius: 4)
        .allowsHitTesting(false)
    }

    private var metricsOverlay: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(116), spacing: 0),
                GridItem(.fixed(116), spacing: 0),
                GridItem(.fixed(116), spacing: 0)
            ],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(appState.overlayMetricDisplayItems) { metric in
                HStack(spacing: 4) {
                    Text(metric.name)
                        .frame(width: 68, alignment: .leading)
                    Text(metric.value)
                        .frame(width: 44, alignment: .leading)
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.lightGray.opacity(appState.hudOpacity))
                .lineLimit(1)
                .frame(width: 116, height: 16, alignment: .leading)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 4)
        .allowsHitTesting(false)
    }

    private var editModeOverlay: some View {
        VStack(spacing: 8) {
            Text("当前处于编辑模式")
                .font(.system(size: 58, weight: .semibold))
            Text("可以调整日志框、状态栏控件的位置和大小")
                .font(.system(size: 20, weight: .semibold))
            Text("右键相关控件可退出编辑状态")
                .font(.system(size: 20, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(0.84))
        .shadow(color: .black.opacity(0.85), radius: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func directionMarkers(size: CGSize) -> some View {
        let frame = HUDOverlayGeometry.directionFrame(in: size)
        let compassSize = frame.width
        let edgeInset = compassSize * 13 / 250
        return ZStack {
            Text("北")
                .position(x: compassSize / 2, y: edgeInset)
            Text("南")
                .position(x: compassSize / 2, y: compassSize - edgeInset)
            Text("西")
                .position(x: edgeInset, y: compassSize / 2)
            Text("东")
                .position(x: compassSize - edgeInset, y: compassSize / 2)
        }
        .font(.system(size: max(12, 34 * size.width / 1920), weight: .semibold))
        .foregroundStyle(Color.white.opacity(appState.hudOpacity))
        .shadow(color: .black.opacity(0.7), radius: 8)
        .frame(width: compassSize, height: compassSize)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private func uidCover(size: CGSize) -> some View {
        let rect = HUDOverlayGeometry.uidCoverRect(in: size)
        return Rectangle()
            .fill(Color.white.opacity(0.92))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

private struct CoreOverlayHUDLayer: View {
    @ObservedObject var store: CoreOverlayStore
    let size: CGSize
    let capturePixelSize: CGSize
    let opacity: Double
    let showMapPoints: Bool
    let showRecognition: Bool
    let skillCdSettings: BetterGICoreSkillCdTriggerSettings?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showMapPoints { mapMaskOverlay }
            if showRecognition { recognitionOverlay }
            skillCdOverlay
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mapMaskOverlay: some View {
        if store.state.isInBigMapUI {
            mapPointCanvas(
                points: store.state.mapPoints,
                viewport: store.state.bigMapViewport,
                diameter: max(20, 32 * size.height / 1080))
            .frame(width: size.width, height: size.height)
        } else {
            let frame = HUDOverlayGeometry.miniMapFrame(in: size)
            mapPointCanvas(
                points: store.state.mapPoints,
                viewport: store.state.miniMapViewport,
                diameter: max(8, min(16, frame.width / 12)))
            .frame(width: frame.width, height: frame.height)
            .clipShape(Circle())
            .position(x: frame.midX, y: frame.midY)
        }
    }

    private func mapPointCanvas(
        points: [CoreOverlayMapPoint], viewport: CGRect?, diameter: CGFloat
    ) -> some View {
        let visiblePoints: [CoreOverlayMapPoint]
        if let viewport, viewport.width > 0, viewport.height > 0 {
            let expandedViewport = viewport.insetBy(dx: -32, dy: -32)
            visiblePoints = points.filter { expandedViewport.contains($0.imagePosition) }
        } else {
            visiblePoints = []
        }
        let iconURLs = Array(Set(visiblePoints.compactMap(\.iconURL)))
            .sorted { $0.absoluteString < $1.absoluteString }
        return Canvas(rendersAsynchronously: false) { context, canvasSize in
            guard let viewport, viewport.width > 0, viewport.height > 0 else { return }
            for point in visiblePoints {
                let center = CGPoint(
                    x: (point.imagePosition.x - viewport.minX) * canvasSize.width / viewport.width,
                    y: (point.imagePosition.y - viewport.minY) * canvasSize.height / viewport.height)
                let rect = CGRect(
                    x: center.x - diameter / 2, y: center.y - diameter / 2,
                    width: diameter, height: diameter)
                var marker = context
                marker.opacity = point.isHidden ? 0.35 : opacity
                marker.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 0.20, green: 0.22, blue: 0.28)))
                marker.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 0.83, green: 0.74, blue: 0.56)),
                    lineWidth: max(1, diameter / 16))
                if let iconURL = point.iconURL,
                   let image = marker.resolveSymbol(id: iconURL.absoluteString) {
                    marker.draw(image, in: rect.insetBy(dx: diameter * 0.12, dy: diameter * 0.12))
                }
            }
        } symbols: {
            ForEach(iconURLs, id: \.absoluteString) { url in
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
                    Color.clear
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .tag(url.absoluteString)
            }
        }
    }

    private var recognitionOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.state.allRectangles) { item in
                let rect = HUDOverlayGeometry.displayRect(
                    item.rect, capturePixelSize: capturePixelSize, in: size)
                Rectangle()
                    .stroke(Color.lime.opacity(opacity), lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            ForEach(store.state.allLabels) { item in
                let rect = HUDOverlayGeometry.displayRect(
                    item.rect, capturePixelSize: capturePixelSize, in: size)
                Rectangle()
                    .stroke((item.recognized ? Color.lime : Color.red).opacity(opacity), lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                Text(item.text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(item.recognized ? Color.lime : Color.red)
                    .shadow(color: .black, radius: 2)
                    .position(x: rect.minX + rect.width / 3, y: max(8, rect.minY - 8))
            }
            ForEach(store.state.allTexts.filter { $0.name != "SkillCdText" }) { item in
                let point = HUDOverlayGeometry.displayPoint(
                    item.position, capturePixelSize: capturePixelSize, in: size)
                Text(item.text)
                    .font(.system(size: max(12, 20 * size.height / 1080), weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(opacity))
                    .shadow(color: .black, radius: 3)
                    .position(point)
            }
        }
    }

    @ViewBuilder
    private var skillCdOverlay: some View {
        if let settings = skillCdSettings {
            ForEach(store.state.allTexts.filter { $0.name == "SkillCdText" }) { item in
                let point = HUDOverlayGeometry.displayPoint(
                    item.position, capturePixelSize: capturePixelSize, in: size)
                let isReady = abs(Double(item.text) ?? 1) < 0.8
                let textColor = Color.skillCd(hex: isReady
                    ? settings.textReadyColor
                    : settings.textNormalColor) ?? (isReady
                        ? Color(red: 93 / 255, green: 204 / 255, blue: 23 / 255)
                        : Color(red: 218 / 255, green: 74 / 255, blue: 35 / 255))
                let backgroundColor = Color.skillCd(hex: isReady
                    ? settings.backgroundReadyColor
                    : settings.backgroundNormalColor) ?? .white
                let displayScale = size.height / 1080 * settings.scale

                Text(item.text)
                    .font(.system(size: max(1, 26 * displayScale), weight: .medium))
                    .foregroundStyle(textColor.opacity(opacity))
                    .padding(.horizontal, max(1, 6 * displayScale))
                    .padding(.vertical, max(1, 2 * displayScale))
                    .background(backgroundColor.opacity(opacity))
                    .clipShape(RoundedRectangle(cornerRadius: max(1, 5 * displayScale)))
                    .position(point)
            }
        }
    }
}

enum HUDOverlayGeometry {
    static func displayRect(_ pixelRect: CGRect, capturePixelSize: CGSize, in displaySize: CGSize) -> CGRect {
        guard capturePixelSize.width > 0, capturePixelSize.height > 0 else { return .zero }
        return CGRect(
            x: pixelRect.minX * displaySize.width / capturePixelSize.width,
            y: pixelRect.minY * displaySize.height / capturePixelSize.height,
            width: pixelRect.width * displaySize.width / capturePixelSize.width,
            height: pixelRect.height * displaySize.height / capturePixelSize.height)
    }

    static func displayPoint(_ pixelPoint: CGPoint, capturePixelSize: CGSize, in displaySize: CGSize) -> CGPoint {
        CGPoint(
            x: pixelPoint.x * displaySize.width / max(1, capturePixelSize.width),
            y: pixelPoint.y * displaySize.height / max(1, capturePixelSize.height))
    }

    static func directionFrame(in size: CGSize) -> CGRect {
        let scale = size.width / 1920
        return CGRect(x: 43 * scale, y: 0, width: 250 * scale, height: 250 * scale)
    }

    static func miniMapFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: 62 * size.width / 1920,
            y: 19 * size.height / 1080,
            width: 212 * size.height / 1080,
            height: 212 * size.height / 1080)
    }

    static func uidCoverRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / 1920, size.height / 1080)
        return CGRect(
            x: size.width - 235 * scale,
            y: size.height - 27 * scale,
            width: 178 * scale,
            height: 22 * scale
        )
    }
}

private extension Color {
    static let lightGray = Color(red: 0.83, green: 0.83, blue: 0.83)
    static let lime = Color(red: 0.2, green: 1.0, blue: 0.2)
}
