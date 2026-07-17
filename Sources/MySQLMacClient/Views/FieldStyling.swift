import SwiftUI

/// The system `.roundedBorder` text field style draws an intentionally
/// subtle 1px outline that all but disappears against light backgrounds —
/// this draws an explicit, app-chosen border instead (the same
/// `gridLineColor` already used for the grid/panel borders elsewhere), so
/// unfocused fields stay clearly legible as fields.
private struct VisibleFieldBorder: ViewModifier {
    var padding: CGFloat = 6
    var cornerRadius: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, padding)
            .padding(.vertical, padding * 0.6)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color(nsColor: .gridLineColor)))
    }
}

extension View {
    func visibleFieldBorder(padding: CGFloat = 6, cornerRadius: CGFloat = 5) -> some View {
        modifier(VisibleFieldBorder(padding: padding, cornerRadius: cornerRadius))
    }
}
