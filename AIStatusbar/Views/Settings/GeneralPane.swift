import SwiftUI

/// General settings: language, launch at login, refresh cadence, status/notification toggles.
/// Mirrors the three grouped sections in the CodexBar mockup: Hệ thống /
/// Sử dụng / Tự động.
struct GeneralPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsLabeledRow(
                    title: "Ngôn ngữ",
                    subtitle: "Khởi động lại app để áp dụng."
                ) {
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(SettingsStore.Language.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    .onChange(of: settings.appLanguage) { _ in
                        settings.applyLanguage()
                    }
                }

                SettingsLabeledRow(
                    title: "Khởi động cùng máy",
                    subtitle: "Tự mở AIStatusbar khi đăng nhập."
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.launchAtLogin) { _ in
                            settings.applyLaunchAtLogin()
                        }
                }
            } header: {
                SettingsSectionHeader(title: "Hệ thống")
            }

            Section {
                SettingsLabeledRow(
                    title: "Tần suất làm mới",
                    subtitle: "Mỗi bao lâu app gọi lại nhà cung cấp."
                ) {
                    Picker("", selection: $settings.refreshIntervalSeconds) {
                        ForEach(SettingsStore.RefreshFrequency.allCases) { f in
                            Text(f.displayName).tag(f.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: settings.refreshIntervalSeconds) { _ in
                        settings.pushRefreshInterval()
                    }
                }
            } header: {
                SettingsSectionHeader(title: "Sử dụng")
            }

            Section {
                SettingsLabeledRow(
                    title: "Kiểm tra trạng thái",
                    subtitle: "Poll trang trạng thái của các nhà cung cấp."
                ) {
                    Toggle("", isOn: $settings.statusChecksEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsLabeledRow(
                    title: "Thông báo phiên 5 giờ",
                    subtitle: "Báo khi phiên quota chạm 0% và khi khôi phục."
                ) {
                    Toggle("", isOn: $settings.sessionQuotaNotificationsEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsLabeledRow(
                    title: "Thông báo cảnh báo quota",
                    subtitle: "Cảnh báo khi còn dưới ngưỡng đã đặt."
                ) {
                    Toggle("", isOn: $settings.quotaWarningNotificationsEnabled).labelsHidden().toggleStyle(.switch)
                }
            } header: {
                SettingsSectionHeader(title: "Tự động")
            }
        }
        
        .scrollContentBackground(.hidden)
    }
}
