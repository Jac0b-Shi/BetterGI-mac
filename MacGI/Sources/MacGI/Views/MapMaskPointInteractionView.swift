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
                    MapMaskPointRightClickTarget(
                        tooltip: marker.point.isHidden
                            ? "右键显示：\(marker.point.label)"
                            : "右键隐藏：\(marker.point.label)"
                    ) {
                        appState.setMapMaskPointHidden(
                            marker.point.sourceID,
                            hidden: !marker.point.isHidden)
                    }
                    .frame(
                        width: marker.rect.width,
                        height: marker.rect.height)
                    .position(
                        x: marker.rect.midX,
                        y: marker.rect.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct MapMaskPointRightClickTarget: NSViewRepresentable {
    let tooltip: String
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> RightClickTargetView {
        RightClickTargetView(tooltip: tooltip, action: action)
    }

    func updateNSView(_ view: RightClickTargetView, context: Context) {
        view.toolTip = tooltip
        view.action = action
    }
}

private final class RightClickTargetView: NSView {
    var action: @MainActor () -> Void

    init(tooltip: String, action: @escaping @MainActor () -> Void) {
        self.action = action
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

    override func rightMouseDown(with event: NSEvent) {
        action()
    }
}
