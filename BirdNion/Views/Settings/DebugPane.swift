import SwiftUI
import AppKit

/// Debug pane. Kept intentionally small — the real diagnostic tools live in
/// CodexBar's full DebugPane (probe logs, fetch strategy, error simulation,
/// caches). This implementation gives BOSS a couple of useful shortcuts:
/// open the config directory and reveal the settings file in Finder.
struct DebugPane: View {
    var body: some View {
        SettingsPage {
            SettingsCard(
                header: "Tệp",
                footer: "Để xem log probe / fetch strategy thật, mở Console.app và filter theo bundle ID."
            ) {
                SettingsLabeledRow(
                    title: "File cấu hình",
                    subtitle: BirdNionConfigStore.configURL().path
                ) {
                    Button("Mở Finder") {
                        let url = BirdNionConfigStore.configURL()
                        // Ensure the parent directory exists so Finder shows
                        // the right folder even on a fresh install.
                        try? FileManager.default.createDirectory(
                            at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
