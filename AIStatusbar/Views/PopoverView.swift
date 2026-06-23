import SwiftUI

/// 280pt popover content — Quota only. Settings opens via AppDelegate from
/// a Cmd+, keyboard shortcut or a future gear button.
struct PopoverView: View {
    @EnvironmentObject var quota: QuotaService
    @State private var settingsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuotaPanel()
        }
        .frame(width: 380, height: 460)
        .background(
            Button(action: { openSettings() }) { EmptyView() }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        )
    }

    private func openSettings() {
        // Forward to AppDelegate via NotificationCenter (avoids coupling Views
        // to AppDelegate directly).
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("com.local.aistatusbar.openSettings")
}
