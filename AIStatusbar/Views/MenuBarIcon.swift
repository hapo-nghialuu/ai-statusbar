import AppKit

/// Renders the menu bar icon by loading `MenuBarIcon` from the asset catalog.
/// The @1x / @2x PNGs are derived from the project's logo (`original.png`)
/// and bundled via `Assets.xcassets/MenuBarIcon.imageset/`.
///
/// Why not an NSImage literal: literal images cannot live inside the binary
/// without an asset catalog, and we want the icon to follow the asset-catalog
/// rules (automatic @1x/@2x selection, dark-mode friendly).
enum MenuBarIconRenderer {
    static let assetName = "MenuBarIcon"

    /// Load the bundled menu bar icon.
    static func image() -> NSImage {
        if let img = NSImage(named: assetName) {
            img.isTemplate = false
            return img
        }
        // Fallback: 1x1 transparent so the status bar slot is not empty if the
        // asset fails to load (e.g. a corrupted build). Should never happen
        // in a properly built .app.
        return NSImage(size: NSSize(width: 22, height: 22))
    }
}