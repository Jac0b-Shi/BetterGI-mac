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

                if appState.showOverlayMapPoints {
                    routeOverlay(size: size)
                    miniMapOverlay(size: size)
                }

                if appState.showOverlayDirections {
                    directionMarkers(size: size)
                }

                if appState.showOverlayRecognition {
                    recognitionOverlay(size: size)
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
        HStack(spacing: 10) {
            ForEach(appState.overlayStatusItems) { item in
                HStack(spacing: 3) {
                    Text(item.glyph)
                        .font(.custom("FgiRegular", size: 12))
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("[\(entry.timeText) \(entry.level.label)]")
                        .foregroundStyle(entry.level.tint)
                    Text(entry.message)
                        .foregroundStyle(Color.lightGray.opacity(appState.hudOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        let compassSize = min(size.width, size.height) * 0.22
        return ZStack {
            Text("北")
                .position(x: compassSize / 2, y: 18)
            Text("南")
                .position(x: compassSize / 2, y: compassSize - 18)
            Text("西")
                .position(x: 18, y: compassSize / 2)
            Text("东")
                .position(x: compassSize - 18, y: compassSize / 2)
        }
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(Color.white.opacity(appState.hudOpacity))
        .shadow(color: .black.opacity(0.7), radius: 8)
        .frame(width: compassSize, height: compassSize)
        .position(x: size.width * 0.14, y: size.height * 0.14)
        .allowsHitTesting(false)
    }

    private func routeOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let points = appState.overlayMapPoints.map {
                CGPoint(x: canvasSize.width * $0.xRatio, y: canvasSize.height * $0.yRatio)
            }

            guard points.count > 1 else { return }

            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(BGIColors.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func miniMapOverlay(size: CGSize) -> some View {
        ZStack {
            ForEach(appState.overlayMapPoints) { point in
                mapPoint(point, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func mapPoint(_ point: OverlayMapPoint, size: CGSize) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(point.tint.opacity(0.9))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
            Text(point.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .shadow(color: .black.opacity(0.75), radius: 6)
        .position(x: size.width * point.xRatio, y: size.height * point.yRatio)
    }

    private func recognitionOverlay(size: CGSize) -> some View {
        ZStack {
            if appState.runtimeSnapshot.observations.isEmpty {
                recognitionBox(
                    title: "RecognitionObject",
                    rect: CGRect(x: size.width * 0.54, y: size.height * 0.62, width: 142, height: 34),
                    tint: BGIColors.success
                )
            } else {
                ForEach(appState.runtimeSnapshot.observations.prefix(6)) { observation in
                    recognitionBox(
                        title: observation.objectName,
                        rect: overlayRect(for: observation.normalizedRect, in: size),
                        tint: tint(for: observation.recognitionType)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func overlayRect(for normalizedRect: CGRect, in size: CGSize) -> CGRect {
        let width = max(44, normalizedRect.width * size.width)
        let height = max(24, normalizedRect.height * size.height)
        return CGRect(
            x: normalizedRect.minX * size.width,
            y: normalizedRect.minY * size.height,
            width: width,
            height: height
        )
    }

    private func tint(for recognitionType: RecognitionType) -> Color {
        switch recognitionType {
        case .templateMatch: BGIColors.success
        case .ocr, .ocrMatch, .colorRangeAndOcr: BGIColors.accent
        case .colorMatch: BGIColors.warning
        case .detect: BGIColors.danger
        case .none: BGIColors.muted
        }
    }

    private func recognitionBox(title: String, rect: CGRect, tint: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(tint.opacity(0.82), lineWidth: 2)
                .background(tint.opacity(0.08))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(x: 0, y: -20)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: .black.opacity(0.5), radius: 4)
    }

    private func uidCover(size: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.92))
            .frame(width: max(90, size.width * 178 / 1920), height: max(12, size.height * 22 / 1080))
            .position(x: size.width - max(118, size.width * 235 / 1920), y: size.height - max(26, size.height * 27 / 1080))
            .allowsHitTesting(false)
    }
}

private extension Color {
    static let lightGray = Color(red: 0.83, green: 0.83, blue: 0.83)
}
