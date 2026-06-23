import AppKit

/// Builds the text shown next to the menu bar icon. The icon itself stays
/// the static bird asset (`MenuBarIcon`); the live number is set as the
/// NSStatusItem button's title so it gets sized and rendered by AppKit.
///
/// Each `(provider, window)` pair is one slot. The status bar cycles
/// through slots every `cycleInterval` seconds via a Timer in AppDelegate.
enum MenuBarIconRenderer {
    static let assetName = "MenuBarIcon"

    /// One slot in the menu bar rotation. The number is the window's
    /// `remainingPct`; `providerName` is the human label (e.g. "AI Hub").
    struct Slot: Equatable {
        let providerName: String
        let windowLabel: String
        let remainingPct: Int
    }

    /// Expand a list of provider statuses into per-window slots. Providers
    /// with no windows (e.g. an error state) contribute nothing.
    static func slots(from statuses: [ProviderStatus]) -> [Slot] {
        statuses.flatMap { status in
            status.windows.map { win in
                Slot(providerName: status.displayName,
                     windowLabel: win.label,
                     remainingPct: win.remainingPct)
            }
        }
    }

    /// Load the bundled menu bar icon (the bird). We deliberately do NOT
    /// set `isTemplate = true` here: that flag would make AppKit redraw
    /// the asset as a single-colour mask, losing the bird's blue colour.
    /// The asset already has the correct alpha and palette for the menu
    /// bar background on both light and dark appearances.
    static func iconImage() -> NSImage {
        if let img = NSImage(named: assetName) {
            img.isTemplate = false
            return img
        }
        return NSImage(size: NSSize(width: 22, height: 22))
    }
}
