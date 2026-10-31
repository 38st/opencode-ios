// Sources: packages/ui/src/actions/{button,icon-button}/*.css;
// forms/switch/switch.css and components/text-field.css. Minimum targets are 44pt on iOS.
import SwiftUI

public struct OCButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case neutral, contrast, submit, ghost, danger }
    let variant: Variant
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(_ variant: Variant = .neutral) { self.variant = variant }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(OCType.button)
            .foregroundStyle(variant == .submit ? OCColor.textInverse : variant == .contrast ? OCColor.textContrast : variant == .danger ? OCColor.danger : OCColor.text)
            .padding(.horizontal, OCSpacing.md).padding(.vertical, OCSpacing.sm)
            .frame(minWidth: OCLayout.touchTarget, minHeight: OCLayout.touchTarget)
            .background(variant == .submit ? OCColor.iconButtonContrast : variant == .contrast ? OCColor.contrast : variant == .ghost ? .clear : OCColor.surface,
                        in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).fill(configuration.isPressed ? OCColor.pressed : .clear))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(variant == .ghost ? .clear : OCColor.borderStrong, lineWidth: OCBorder.hairline))
            .opacity(enabled ? 1 : variant == .submit ? 0.4 : 0.5)
            .contentShape(Rectangle())
            .ocHover(RoundedRectangle(cornerRadius: OCRadius.md))
            .animation(reduceMotion ? nil : .easeOut(duration: OCMotion.fast), value: configuration.isPressed)
    }
}
public extension View {
    /// The iPad pointer's highlight, in the control's own shape.
    @ViewBuilder func ocHover(_ shape: some Shape = RoundedRectangle(cornerRadius: OCRadius.md)) -> some View {
        #if os(iOS)
        contentShape(.hoverEffect, shape).hoverEffect(.highlight)
        #else
        self
        #endif
    }
}
public struct OCSubmitIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: OCComposerMetrics.submit, height: OCComposerMetrics.submit)
            .foregroundStyle(OCColor.textInverse)
            .background(OCColor.iconButtonContrast, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).fill(configuration.isPressed ? OCColor.pressed : .clear))
            .opacity(enabled ? 1 : 0.4)
            .frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget).contentShape(Rectangle())
            .ocHover()
    }
}
public struct OCIconButton: View {
    let title: String
    let icon: String
    let role: ButtonRole?
    let action: () -> Void
    public init(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.role = role; self.action = action
    }
    public var body: some View {
        // Native toolbars may flatten custom ButtonStyle backgrounds into a
        // template image, turning the entire hit target into a solid rectangle.
        Button(role: role, action: action) {
            OCIcon(icon).frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget).contentShape(Rectangle()).ocHover()
        }.buttonStyle(.plain).tint(role == .destructive ? OCColor.danger : OCColor.text)
            .foregroundStyle(role == .destructive ? OCColor.danger : OCColor.text)
            .accessibilityLabel(title).help(title)
    }
}
public struct OCTextFieldStyle: TextFieldStyle {
    let font: Font
    public init(font: Font = OCType.body) { self.font = font }
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(font).foregroundStyle(OCColor.text)
            .padding(.horizontal, OCSpacing.md).padding(.vertical, OCSpacing.sm)
            .frame(minHeight: OCLayout.touchTarget)
            .background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.borderStrong, lineWidth: OCBorder.standard))
    }
}
public struct OCToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    public init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.detail = detail; _isOn = isOn
    }
    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(title).font(OCType.body)
                if let detail { Text(detail).font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true) }
            }
        }.toggleStyle(OCToggleStyle()).frame(minHeight: OCLayout.touchTarget)
    }
}
#Preview("Controls") {
    VStack(spacing: OCSpacing.lg) {
        Button("Connect") {}.buttonStyle(OCButtonStyle(.contrast))
        Button("Cancel") {}.buttonStyle(OCButtonStyle())
        Button("Remove server") {}.buttonStyle(OCButtonStyle(.danger))
        OCIconButton("Add server", icon: "plus") {}
        TextField("Server URL", text: .constant("")).textFieldStyle(OCTextFieldStyle())
        OCToggleRow("Notifications", isOn: .constant(true))
    }.padding().ocTheme()
}

// Source: packages/app/src/shell tabs and session-review-v2.css. The selected tab is a filled pill with the base
// text colour; `pressed` composites to the reference's #e6e6e6 on light surfaces and stays visible on every layer,
// unlike layer1, which equals backgroundDeep in light mode.
public struct OCTabStyle: ButtonStyle {
    let selected: Bool
    let fill: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(selected: Bool, fill: Bool = false) { self.selected = selected; self.fill = fill }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(OCType.button).foregroundStyle(selected ? OCColor.text : OCColor.textMuted)
            .padding(.horizontal, fill ? OCSpacing.xs : OCSpacing.md).frame(maxWidth: fill ? .infinity : nil).frame(minHeight: OCLayout.touchTarget)
            .background(selected ? OCColor.pressed : configuration.isPressed ? OCColor.hover : .clear, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .contentShape(Rectangle())
            .ocHover()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .animation(reduceMotion ? nil : .easeOut(duration: OCMotion.fast), value: configuration.isPressed)
    }
}

// Source: packages/ui/src/navigation/segmented-control/segmented-control.css. At accessibility sizes options stack,
// retaining their full labels and the selected trait instead of truncating.
public struct OCSegmentedControl<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    let equalWidth: Bool
    @Binding var selection: Value
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ title: String, options: [(Value, String)], selection: Binding<Value>, equalWidth: Bool = true) {
        self.title = title; self.options = options; _selection = selection; self.equalWidth = equalWidth
    }
    public var body: some View {
        let layout = typeSize.isAccessibilitySize && equalWidth ? AnyLayout(VStackLayout(spacing: OCSpacing.xs)) : AnyLayout(HStackLayout(spacing: OCSpacing.xs))
        layout {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.0 } label: {
                    Text(option.1).lineLimit(equalWidth ? nil : 1).fixedSize(horizontal: !equalWidth, vertical: false)
                }.buttonStyle(OCTabStyle(selected: selection == option.0, fill: equalWidth))
            }
        }.padding(OCSpacing.xs)
            .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

private struct OCToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: OCSpacing.sm) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: OCRadius.sm)
                    .fill(configuration.isOn ? OCColor.accentBackground : OCColor.layer4)
                    .frame(width: 24, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: OCRadius.xs).fill(OCTheme.openCode.color("toggleThumb"))
                            .frame(width: 12, height: 12).padding(2)
                    }
            }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeOut(duration: OCMotion.toggle), value: configuration.isOn)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }
}
