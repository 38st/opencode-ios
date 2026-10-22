// Sources: packages/ui/src/actions/{button,icon-button}/*.css;
// forms/switch/switch.css and components/text-field.css. Minimum targets are 44pt on iOS.
import SwiftUI

public struct OCButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case neutral, contrast, ghost, danger }
    let variant: Variant
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(_ variant: Variant = .neutral) { self.variant = variant }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(OCType.button)
            .foregroundStyle(variant == .contrast ? OCColor.textContrast : variant == .danger ? OCColor.danger : OCColor.text)
            .padding(.horizontal, OCSpacing.md).padding(.vertical, OCSpacing.sm)
            .frame(minWidth: OCLayout.touchTarget, minHeight: OCLayout.touchTarget)
            .background(variant == .contrast ? OCColor.contrast : variant == .ghost ? .clear : OCColor.surface,
                        in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).fill(configuration.isPressed ? OCColor.pressed : .clear))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(variant == .ghost ? .clear : OCColor.borderStrong, lineWidth: OCBorder.hairline))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: OCMotion.fast), value: configuration.isPressed)
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
            OCIcon(icon).frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget).contentShape(Rectangle())
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
                if let detail { Text(detail).font(OCType.small).foregroundStyle(OCColor.textMuted) }
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
                    Text(option.1).font(OCType.button).lineLimit(equalWidth ? nil : 1)
                        .fixedSize(horizontal: !equalWidth, vertical: false).padding(.horizontal, equalWidth ? 0 : OCSpacing.sm).frame(maxWidth: equalWidth ? .infinity : nil)
                        .frame(minHeight: OCLayout.touchTarget)
                        .contentShape(Rectangle())
                        .background(selection == option.0 ? OCColor.background : .clear, in: RoundedRectangle(cornerRadius: OCRadius.sm))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }.padding(OCSpacing.xs).background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
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
