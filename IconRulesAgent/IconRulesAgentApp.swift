import SwiftUI
import AppKit

@main
struct IconRulesAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate let service = IconRulesService()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        service.start()

        // Enable Dock icon and foreground activation, so you can drag .app bundles to the Dock icon
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Menu bar icon + menu
        statusBar = StatusBarController(service: service)

        Logger.shared.info("App launched.")
        Logger.shared.info("rulesWatchDir=\(service.rulesWatchDir.path)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Logger.shared.info("Open URLs received: count=\(urls.count) baseDir=\(service.rulesWatchDir.path)")
        for u in urls { Logger.shared.info("  URL: \(u.path)") }
        IconDropHandler.shared.handle(urls: urls, baseRulesDir: service.rulesWatchDir)
    }
}
