import AppKit
import SwiftUI

/// `NSColor` ↔ `"#RRGGBB"` hex conversion for the settings' color storage,
/// plus the `Binding<Color>` bridge SwiftUI's `ColorPicker` needs.
extension NSColor {
    /// nil for strings that aren't `#RRGGBB` (callers fall back to a
    /// default rather than crashing on a hand-edited settings.json).
    convenience init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }

    /// `#RRGGBB` in sRGB; alpha is dropped (settings colors are opaque).
    var hexString: String {
        let srgb = usingColorSpace(.sRGB) ?? self
        let red = Int(round(srgb.redComponent * 255))
        let green = Int(round(srgb.greenComponent * 255))
        let blue = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", red, green, blue)
    }

    /// Resolves an `AdaptiveColorSetting` per the *current effective*
    /// appearance at draw time — same dynamic-provider pattern as
    /// `NSColor.adaptive(light:dark:)`, but reading the hex pair inside the
    /// closure so settings changes show up on the very next draw without
    /// anyone having to invalidate cached color objects.
    ///
    /// Takes a `@Sendable` selector closure rather than a `KeyPath` —
    /// key-path values aren't `Sendable`, and only the (Sendable) selected
    /// struct may cross the `assumeIsolated` boundary. Providers run on the
    /// main thread at draw time, so the assumption holds.
    static func settingsColor(
        _ select: @escaping @Sendable (AppSettings) -> AdaptiveColorSetting,
        fallback: NSColor
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let setting = MainActor.assumeIsolated { select(SettingsStore.shared.settings) }
            return NSColor(hexString: isDark ? setting.dark : setting.light) ?? fallback
        }
    }
}

extension AdaptiveColorSetting {
    /// A `ColorPicker`-compatible binding into one side (light or dark) of
    /// an adaptive color stored on the settings object.
    @MainActor
    static func binding(
        _ store: SettingsStore,
        _ keyPath: WritableKeyPath<AppSettings, AdaptiveColorSetting>,
        dark: Bool
    ) -> Binding<Color> {
        Binding<Color>(
            get: {
                let setting = store.settings[keyPath: keyPath]
                let hex = dark ? setting.dark : setting.light
                return Color(nsColor: NSColor(hexString: hex) ?? .labelColor)
            },
            set: { newColor in
                let hex = NSColor(newColor).hexString
                if dark {
                    store.settings[keyPath: keyPath].dark = hex
                } else {
                    store.settings[keyPath: keyPath].light = hex
                }
            }
        )
    }
}
