// Source: packages/ui/src/resize-handle (ResizeHandle). On iPad the pointer becomes the system's resize arrows.
#if os(iOS)
import SwiftUI
import UIKit

public struct OCResizeHandle: View {
    public enum Style: Sendable {
        /// The 6-pt rule between a file tree and its content.
        case rule
        /// The gap between two workspace panels.
        case gap
    }
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let reset: Double
    /// The resized panel's side: a leading panel grows when the handle moves right.
    let edge: HorizontalEdge
    let style: Style
    @State private var start: Double?
    public init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, reset: Double, edge: HorizontalEdge = .leading, style: Style = .rule) {
        self.title = title; _value = value; self.range = range; self.reset = reset; self.edge = edge; self.style = style
    }
    public var body: some View {
        Group {
            switch style {
            case .rule: Rectangle().fill(OCColor.border).frame(width: 6).contentShape(Rectangle().inset(by: -19))
            case .gap: Color.clear.frame(width: OCSpacing.sm).contentShape(Rectangle().inset(by: -6))
            }
        }
        .background { ResizePointerRegion().frame(width: style == .rule ? 20 : OCSpacing.sm + 12) }
        .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
            let origin = start ?? value
            if start == nil { start = origin }
            value = clamp(origin + (edge == .leading ? drag.translation.width : -drag.translation.width))
        }.onEnded { _ in start = nil })
        .onTapGesture(count: 2) { value = clamp(reset) }
        .accessibilityElement().accessibilityLabel(title).accessibilityValue(localized("\(Int(value)) points", comment: "Panel width; %lld is a number of screen points"))
        .accessibilityAdjustableAction { direction in value = clamp(value + (direction == .increment ? 20 : -20)) }
    }
    private func clamp(_ next: Double) -> Double { min(max(next, range.lowerBound), max(range.lowerBound, range.upperBound)) }
}

/// Shows iPadOS's resize pointer: a vertical beam with arrows to either side.
private struct ResizePointerRegion: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.addInteraction(UIPointerInteraction(delegate: context.coordinator))
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIPointerInteractionDelegate {
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            let style = UIPointerStyle(shape: .verticalBeam(length: 24), constrainedAxes: .vertical)
            style.accessories = [UIPointerAccessory.arrow(.left), UIPointerAccessory.arrow(.right)]
            return style
        }
    }
}
#endif
