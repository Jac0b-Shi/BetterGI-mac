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
        EmptyView()
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

enum HUDOverlayGeometry {
    static func directionFrame(in size: CGSize) -> CGRect {
        let scale = size.width / 1920
        return CGRect(x: 43 * scale, y: 0, width: 250 * scale, height: 250 * scale)
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
}
