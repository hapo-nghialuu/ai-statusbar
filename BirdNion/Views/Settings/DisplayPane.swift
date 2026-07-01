import SwiftUI

/// Display settings for the status item in the macOS menu bar.
struct DisplayPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        SettingsPage {
            SettingsCard(
                header: L10n.t("settings.section.menuBar", settings.appLanguage),
                footer: LocalizedStringKey(L10n.t("settings.display.footer", settings.appLanguage))
            ) {
                SettingsLabeledRow(
                    title: L10n.t("settings.showPercentInMenuBar.title", settings.appLanguage),
                    subtitle: L10n.t("settings.showPercentInMenuBar.subtitle", settings.appLanguage)
                ) {
                    Toggle("", isOn: $settings.showPercentInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}
