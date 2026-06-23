import AppKit
import SwiftUI
import Combine

/// AppDelegate creates the NSStatusItem (menu bar icon) programmatically and
/// manages an NSPopover for the popover content. The menu bar icon is a
/// dynamic NSImage redrawn from the latest QuotaService statuses (codexbar
/// "usage meter drawn dynamically" approach).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = ServicesContainer()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        services.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings(_:)),
            name: .openSettings, object: nil
        )

        // Status bar item — dynamic equalizer icon, redrawn on every quota update
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        refreshIcon()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // Popover — transient behavior: click outside → auto-close
        popover = NSPopover()
        popover.behavior = .transient
        popover.pinned = false   // explicit: not a "utility" pinned popover
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 460)
        let host = NSHostingController(
            rootView: PopoverView()
                .environmentObject(services.quotaService)
                .environmentObject(services.configService)
                .environmentObject(services.keychain)
        )
        popover.contentViewController = host

        // Re-render icon whenever QuotaService publishes a new status
        services.quotaService.$statuses
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        let image = MenuBarIconRenderer.image()
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.imagePosition = .imageOnly
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    // Settings via Cmd+, — opens a regular AppKit window
    @objc func openSettings(_ sender: AnyObject?) {
        if settingsWindow == nil {
            let host = NSHostingController(
                rootView: SettingsWindow()
                    .environmentObject(services.quotaService)
                    .environmentObject(services.configService)
                    .environmentObject(services.keychain)
            )
            settingsWindow = NSWindow(contentViewController: host)
            settingsWindow?.title = "AI Statusbar — Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 420, height: 300))
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
    }
}
