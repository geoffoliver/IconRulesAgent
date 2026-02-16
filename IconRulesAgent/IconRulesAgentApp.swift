import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

        // Hide Dock icon; keep app running as an accessory with only a menu bar item
        NSApp.setActivationPolicy(.accessory)

        // Menu bar icon + menu
        statusBar = StatusBarController(service: service)
        DropWindowController.shared.configure(with: service)

        Logger.shared.info("App launched.")
        Logger.shared.info("rulesWatchDir=\(service.rulesWatchDir.path)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Logger.shared.info("Open URLs received: count=\(urls.count) baseDir=\(service.rulesWatchDir.path)")
        for u in urls { Logger.shared.info("  URL: \(u.path)") }
        IconDropHandler.shared.handle(urls: urls, baseRulesDir: service.rulesWatchDir)
    }
}
import Combine

final class DropWindowController: NSObject, NSWindowDelegate {
    static let shared = DropWindowController()

    private var window: NSWindow?
    private var service: IconRulesService?

    func configure(with service: IconRulesService) {
        self.service = service
    }

    func showWindow() {
        if window == nil {
            let content = DropAppView(baseRulesDir: service?.rulesWatchDir)
            let hosting = NSHostingView(rootView: content)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered,
                               defer: false)
            win.title = "Drop Your App Here"
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = hosting
            win.delegate = self
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // keep window instance for reuse
    }
}

struct DropAppView: View {
    let baseRulesDir: URL?
    @State private var isTargeted = false
    @State private var dropMessage = "Drop a .app bundle here"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .opacity(0.9)

            Text("Drop Your App Here")
                .font(.title2)
                .bold()

            Text("Drag a .app bundle into this window to add it to your rules.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                .padding(24)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        let group = DispatchGroup()
        var urls: [URL] = []
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
            handled = true
        }
        group.notify(queue: .main) {
            let appURLs = urls.filter { $0.pathExtension.lowercased() == "app" }
            if !appURLs.isEmpty, let baseDir = baseRulesDir {
                IconDropHandler.shared.handle(urls: appURLs, baseRulesDir: baseDir)
            }
        }
        return handled
    }
}

