import AppKit
import Foundation

final class IconDropHandler {
    static let shared = IconDropHandler()

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let log = Logger.shared

    func handle(urls: [URL], baseRulesDir: URL) {
        log.info("Handling drop: urls=\(urls.map { $0.path }) baseRulesDir=\(baseRulesDir.path)")
        ensureBaseDir(baseRulesDir: baseRulesDir)
        for url in urls where url.pathExtension.lowercased() == "app" {
            handleAppBundle(url, baseRulesDir: baseRulesDir)
        }
    }

    private func ensureBaseDir(baseRulesDir: URL) {
        try? fm.createDirectory(at: baseRulesDir, withIntermediateDirectories: true)
        log.info("Ensured base rules dir exists at: \(baseRulesDir.path)")
    }

    private func handleAppBundle(_ appURL: URL, baseRulesDir: URL) {
        let appName = appURL.deletingPathExtension().lastPathComponent
        log.info("Processing app bundle: name=\(appName) path=\(appURL.path)")
        let ruleDir = baseRulesDir.appendingPathComponent(appName, isDirectory: true)
        try? fm.createDirectory(at: ruleDir, withIntermediateDirectories: true)
        log.info("Ensured rule dir: \(ruleDir.path)")

        let ruleConf = ruleDir.appendingPathComponent("rule.conf", isDirectory: false)
        log.info("Rule config path: \(ruleConf.path)")
        let newLine = "target=\(appURL.path)\n"

        if let existing = try? String(contentsOf: ruleConf, encoding: .utf8) {
            let normalized = existing.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let newNorm = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.contains(newNorm) {
                try? (existing + (existing.hasSuffix("\n") ? "" : "\n") + newLine).write(to: ruleConf, atomically: true, encoding: .utf8)
                log.info("Added target to \(ruleConf.path): \(appURL.path)")
            } else {
                log.info("Target already present in \(ruleConf.path): \(appURL.path)")
            }
        } else {
            try? newLine.write(to: ruleConf, atomically: true, encoding: .utf8)
            log.info("Created \(ruleConf.path) with target \(appURL.path)")
        }

        log.info("Opening rule dir in Finder: \(ruleDir.path)")
        NSWorkspace.shared.open(ruleDir)
    }
}
