import AppKit
import Foundation

final class IconRulesService {
    private let fm = FileManager.default
    private let applier = IconApplier()
    private let rulesWatcher = FSEventsWatcher()
    private let appsWatcher = FSEventsWatcher()
    private var configWatcher: DispatchSourceFileSystemObject?

    private let log = Logger.shared

    private let configDir: URL
    private let configPath: URL

    private var config: AppIconConfig = .defaultConfig()
    // Expose the rules watch directory without exposing the full config
    var rulesWatchDir: URL { config.watchDir }
    private var pendingWorkItem: DispatchWorkItem?

    init() {
        let home = fm.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".icons", isDirectory: true)
        configPath = configDir.appendingPathComponent("config.conf", isDirectory: false)
    }

    func start() {
        log.info("Service.start() configDir=\(configDir.path) configPath=\(configPath.path)")
        ensureDirectories()
        reloadConfigAndRestartWatchers()
        log.info("Service started. Watching rules at \(config.watchDir.path)")
        applier.applyRules(config: config, changedPath: nil)
    }

    func openRulesFolder() {
        NSWorkspace.shared.open(config.watchDir)
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(log.logsDirectoryURL())
    }

    func reloadConfig() {
        ensureDirectories()
        reloadConfigAndRestartWatchers()
        applier.applyRules(config: config, changedPath: nil)
        log.info("Manual reload requested.")
    }

    private func ensureDirectories() {
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        log.info("Ensured config dir at: \(configDir.path)")
        try? fm.createDirectory(at: AppIconConfig.defaultConfig().watchDir, withIntermediateDirectories: true)
        log.info("Ensured default watch dir at: \(AppIconConfig.defaultConfig().watchDir.path)")

        if !fm.fileExists(atPath: configPath.path) {
            let defaultText = """
            # IconRulesAgent config (edits auto-reload)

            # Directory to watch for rule folders:
            watch_dir=~/.icons/icons

            # Also check ~/Applications in addition to /Applications:
            include_user_applications=true

            # Debounce file bursts (ms):
            debounce_ms=350
            """
            try? defaultText.data(using: .utf8)?.write(to: configPath, options: [.atomic])
            log.info("Wrote default config to: \(configPath.path)")
        }
    }

    private func reloadConfigAndRestartWatchers() {
        let newConfig = AppIconConfig.load(from: configPath)
        log.info("Loaded config: watch_dir=\(newConfig.watchDir.path) include_user_applications=\(newConfig.includeUserApplications) debounce_ms=\(newConfig.debounceMilliseconds)")
        try? fm.createDirectory(at: newConfig.watchDir, withIntermediateDirectories: true)
        log.info("Ensured configured watch dir at: \(newConfig.watchDir.path)")

        let old = config
        config = newConfig

        rulesWatcher.startWatching(path: config.watchDir) { [weak self] changed in
            self?.debouncedApply(changedPath: changed)
        }

        // Watch /Applications so app updates/reinstalls re-apply icons
        let sysApps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        appsWatcher.startWatching(path: sysApps) { [weak self] changed in
            self?.handleApplicationsChange(changedPath: changed)
        }

        startConfigWatcher()

        if old != newConfig {
            log.info("Config changed. watch_dir=\(newConfig.watchDir.path) include_user_applications=\(newConfig.includeUserApplications) debounce_ms=\(newConfig.debounceMilliseconds)")
            applier.applyRules(config: newConfig, changedPath: nil)
        }
    }

    private func startConfigWatcher() {
        configWatcher?.cancel()
        configWatcher = nil

        guard let fh = try? FileHandle(forReadingFrom: configPath) else { return }
        let fd = fh.fileDescriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.log.info("Config file changed; reloading.")
            self.ensureDirectories()
            self.reloadConfigAndRestartWatchers()
        }

        src.setCancelHandler {
            close(fd)
        }

        configWatcher = src
        src.resume()
    }

    private func debouncedApply(changedPath: URL?) {
        pendingWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applier.applyRules(config: self.config, changedPath: changedPath)
        }
        pendingWorkItem = item

        let delay = DispatchTimeInterval.milliseconds(config.debounceMilliseconds)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func handleApplicationsChange(changedPath: URL?) {
        guard let changedPath else {
            applier.applyRules(config: config, changedPath: nil)
            return
        }

        let comps = changedPath.path.split(separator: "/").map(String.init)
        if let idx = comps.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appPath = "/" + comps.prefix(idx + 1).joined(separator: "/")
            applier.applyForAppBundleChange(config: config, appBundlePath: URL(fileURLWithPath: appPath, isDirectory: true))
        } else {
            applier.applyRules(config: config, changedPath: nil)
        }
    }
}
