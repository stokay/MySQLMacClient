import SwiftUI
import AppKit

extension Image {
    /// Loads a PNG bundled as a plain SwiftPM resource copy (see
    /// `Package.swift`'s `.copy("Resources")`) — not an `.xcassets` catalog,
    /// since asset-catalog symbol codegen (`Image(.name)`) needs Xcode's
    /// build system and this package builds via `swift build` on the
    /// command line.
    static func bundled(_ name: String, fallbackSystemImage: String) -> Image {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
            let nsImage = NSImage(contentsOf: url)
        else {
            return Image(systemName: fallbackSystemImage)
        }
        return Image(nsImage: nsImage)
    }
}
