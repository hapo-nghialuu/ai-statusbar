import SwiftUI

/// Custom horizontal tab bar with icon + 2-line label, matching the CodexBar
/// toolbar style. Selected tab uses `.tint`; others use `.secondary`.
struct SettingsTabBar: View {
    @Binding var selected: SettingsTab
    let tabs: [SettingsTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: tab == selected,
                    action: { selected = tab }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .regular))
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.12)
                          : (hovering ? Color.gray.opacity(0.08) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
