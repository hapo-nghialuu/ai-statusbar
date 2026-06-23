import SwiftUI

/// Display settings: how icons are merged/rotated in the menu bar.
/// Today the renderer always uses a single bird icon — these settings are
/// persisted but have no visual effect yet (YAGNI wiring).
struct DisplayPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsLabeledRow(
                    title: "Gộp icon nhà cung cấp",
                    subtitle: "Hiện một icon duy nhất xoay vòng giữa các provider."
                ) {
                    Toggle("", isOn: $settings.mergeIcons).labelsHidden().toggleStyle(.switch)
                }
                SettingsLabeledRow(
                    title: "Switcher có icon",
                    subtitle: settings.mergeIcons
                        ? "Hiện icon khi chuyển nhà cung cấp từ popover."
                        : "Bật “Gộp icon” trước."
                ) {
                    Toggle("", isOn: $settings.switcherShowsIcons)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!settings.mergeIcons)
                }
            } header: {
                SettingsSectionHeader(title: "Menu bar")
            } footer: {
                Text("Cài đặt này sẽ có hiệu lực khi trình render hỗ trợ multi-icon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
