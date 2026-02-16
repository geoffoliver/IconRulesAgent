import AppKit
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private weak var service: IconRulesService?

    init(service: IconRulesService) {
        self.service = service
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "IconRulesAgent")
        }

        let menu = NSMenu()

        let openDrop = NSMenuItem(title: "Add App…", action: #selector(showDropWindow), keyEquivalent: "d")
        openDrop.target = self
        menu.addItem(openDrop)

        menu.addItem(NSMenuItem.separator())

        let openRules = NSMenuItem(title: "Open Rules Folder", action: #selector(openRulesFolder), keyEquivalent: "o")
        openRules.target = self
        menu.addItem(openRules)

        let openLogs = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogsFolder), keyEquivalent: "l")
        openLogs.target = self
        menu.addItem(openLogs)

        menu.addItem(NSMenuItem.separator())

        let reload = NSMenuItem(title: "Reload Config & Reapply", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func openRulesFolder() { service?.openRulesFolder() }
    @objc private func openLogsFolder() { service?.openLogsFolder() }
    @objc private func reloadConfig() { service?.reloadConfig() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func showDropWindow() {
        DropWindowController.shared.showWindow()
    }
}
