import AppKit
import SwiftUI

enum MapMaskPointInteractionGeometry {
    struct MarkerRect {
        let point: CoreOverlayMapPoint
        let rect: CGRect
    }

    static func markerRects(
        points: [CoreOverlayMapPoint],
        viewport: CGRect?,
        size: CGSize
    ) -> [MarkerRect] {
        guard let viewport, viewport.width > 0, viewport.height > 0,
              size.width > 0, size.height > 0 else {
            return []
        }
        let expandedViewport = viewport.insetBy(dx: -32, dy: -32)
        let diameter = max(20, 32 * size.height / 1080)
        return points.compactMap { point in
            guard expandedViewport.contains(point.imagePosition) else {
                return nil
            }
            let center = CGPoint(
                x: (point.imagePosition.x - viewport.minX)
                    * size.width / viewport.width,
                y: (point.imagePosition.y - viewport.minY)
                    * size.height / viewport.height)
            return MarkerRect(
                point: point,
                rect: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter))
        }
    }

    static func containsMarker(
        at displayPoint: CGPoint,
        points: [CoreOverlayMapPoint],
        viewport: CGRect?,
        size: CGSize
    ) -> Bool {
        guard let viewport, viewport.width > 0, viewport.height > 0,
              size.width > 0, size.height > 0 else {
            return false
        }
        let diameter = max(20, 32 * size.height / 1080)
        let halfImageWidth = diameter * viewport.width / size.width / 2
        let halfImageHeight = diameter * viewport.height / size.height / 2
        let imagePoint = CGPoint(
            x: viewport.minX + displayPoint.x * viewport.width / size.width,
            y: viewport.minY + displayPoint.y * viewport.height / size.height)
        return points.contains { point in
            abs(point.imagePosition.x - imagePoint.x) <= halfImageWidth
                && abs(point.imagePosition.y - imagePoint.y) <= halfImageHeight
        }
    }

    static func popupFrame(
        pointID: String,
        points: [CoreOverlayMapPoint],
        viewport: CGRect?,
        size: CGSize
    ) -> CGRect? {
        guard let marker = markerRects(
            points: points, viewport: viewport, size: size
        ).first(where: { $0.point.sourceID == pointID }) else {
            return nil
        }
        let scale = max(0.75, size.height / 1080)
        let width = min(max(300, 360 * scale), max(0, size.width - 24))
        let height = min(max(320, 520 * scale), max(0, size.height - 24))
        let x = min(
            max(12, marker.rect.midX - width / 2),
            max(12, size.width - width - 12))
        let preferredY = marker.rect.minY - height - 8
        let y = preferredY >= 12
            ? preferredY
            : min(marker.rect.maxY + 8, max(12, size.height - height - 12))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct MapMaskPointInteractionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            let markers = MapMaskPointInteractionGeometry.markerRects(
                points: appState.coreOverlayStore.state.mapPoints,
                viewport: appState.coreOverlayStore.state.bigMapViewport,
                size: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(markers, id: \.point.id) { marker in
                    MapMaskPointInteractionTarget(
                        tooltip: marker.point.isHidden
                            ? "查看详情；右键显示：\(marker.point.label)"
                            : "查看详情；右键隐藏：\(marker.point.label)",
                        leftAction: {
                            appState.showMapMaskPointDetail(
                                marker.point.sourceID)
                        },
                        rightAction: {
                        appState.setMapMaskPointHidden(
                            marker.point.sourceID,
                            hidden: !marker.point.isHidden)
                        })
                    .frame(
                        width: marker.rect.width,
                        height: marker.rect.height)
                    .position(
                        x: marker.rect.midX,
                        y: marker.rect.midY)
                }
                if let pointID = appState.selectedMapMaskPointID,
                   let frame = MapMaskPointInteractionGeometry.popupFrame(
                    pointID: pointID,
                    points: appState.coreOverlayStore.state.mapPoints,
                    viewport: appState.coreOverlayStore.state.bigMapViewport,
                    size: proxy.size),
                   let point = markers.first(where: {
                       $0.point.sourceID == pointID
                   })?.point {
                    pointDetailPopup(point)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func pointDetailPopup(_ point: CoreOverlayMapPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(appState.mapMaskPointDetail?.title ?? point.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    appState.setMapMaskPointHidden(
                        point.sourceID, hidden: !point.isHidden)
                } label: {
                    Label(
                        point.isHidden ? "显示" : "隐藏",
                        systemImage: point.isHidden ? "eye" : "eye.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: appState.closeMapMaskPointDetail) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }

            Divider()

            if appState.mapMaskPointDetailLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载文本...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = appState.mapMaskPointDetailError {
                Text(error)
                    .foregroundStyle(.secondary)
            } else if let detail = appState.mapMaskPointDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !detail.links.isEmpty {
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: 88),
                                        spacing: 8,
                                        alignment: .leading)
                                ],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(detail.links) { link in
                                    Button(link.text) {
                                        appState.openMapMaskPointLink(link.url)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(link.url)
                                }
                            }
                        }

                        if let imageURL = normalizedWebURL(detail.imageURL) {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView("图片加载中...")
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: 100)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                case .failure:
                                    Text("图片加载失败")
                                        .foregroundStyle(.secondary)
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: 80)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }

                        Text(detail.text)
                            .foregroundStyle(Color.white.opacity(0.90))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 18)
    }

    private func normalizedWebURL(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.hasPrefix("//") ? "https:\(text)"
            : text.lowercased().hasPrefix("www.") ? "https://\(text)"
            : text
        guard let url = URL(string: normalized),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }
}

private struct MapMaskPointInteractionTarget: NSViewRepresentable {
    let tooltip: String
    let leftAction: @MainActor () -> Void
    let rightAction: @MainActor () -> Void

    func makeNSView(context: Context) -> InteractionTargetView {
        InteractionTargetView(
            tooltip: tooltip,
            leftAction: leftAction,
            rightAction: rightAction)
    }

    func updateNSView(_ view: InteractionTargetView, context: Context) {
        view.toolTip = tooltip
        view.leftAction = leftAction
        view.rightAction = rightAction
    }
}

private final class InteractionTargetView: NSView {
    var leftAction: @MainActor () -> Void
    var rightAction: @MainActor () -> Void

    init(
        tooltip: String,
        leftAction: @escaping @MainActor () -> Void,
        rightAction: @escaping @MainActor () -> Void
    ) {
        self.leftAction = leftAction
        self.rightAction = rightAction
        super.init(frame: .zero)
        toolTip = tooltip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        leftAction()
    }

    override func rightMouseDown(with event: NSEvent) {
        rightAction()
    }
}
