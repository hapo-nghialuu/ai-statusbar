import SwiftUI

/// 1×1 keep-alive window so SwiftUI's lifecycle stays alive when the only
/// top-level scene is `Settings`. Without this the native toolbar can fail
/// to render in some AppKit-backed shells — same trick CodexBar uses in
/// `CodexbarApp.swift`.
struct HiddenWindowView: View {
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
    }
}
