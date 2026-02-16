import Foundation

final class Logger {
    static let shared = Logger()

    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "icons.logger.queue", qos: .utility)

    private let logsDir: URL
    private let logFile: URL
    private let maxBytes: Int = 2_000_000 // ~2MB
    private let keepRotations: Int = 3

    private init() {
        let home = fm.homeDirectoryForCurrentUser
        logsDir = home.appendingPathComponent("Library/Logs/IconRulesAgent", isDirectory: true)
        logFile = logsDir.appendingPathComponent("IconRulesAgent.log", isDirectory: false)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func logsDirectoryURL() -> URL { logsDir }
    func logFileURL() -> URL { logFile }

    func info(_ message: String) { write(level: "INFO", message: message) }
    func warn(_ message: String) { write(level: "WARN", message: message) }
    func error(_ message: String) { write(level: "ERROR", message: message) }

    private func write(level: String, message: String) {
        queue.async {
            self.rotateIfNeeded()

            let ts = ISO8601DateFormatter().string(from: Date())
            let line = "[\(ts)] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if self.fm.fileExists(atPath: self.logFile.path) {
                if let fh = try? FileHandle(forWritingTo: self.logFile) {
                    defer { try? fh.close() }
                    do {
                        try fh.seekToEnd()
                        try fh.write(contentsOf: data)
                    } catch {
                        // best-effort
                    }
                }
            } else {
                try? data.write(to: self.logFile, options: [.atomic])
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? fm.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? NSNumber
        else { return }

        if size.intValue < maxBytes { return }

        for i in stride(from: keepRotations, through: 1, by: -1) {
            let src = logsDir.appendingPathComponent("IconRulesAgent.log.\(i)", isDirectory: false)
            let dst = logsDir.appendingPathComponent("IconRulesAgent.log.\(i+1)", isDirectory: false)
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            if fm.fileExists(atPath: src.path) { try? fm.moveItem(at: src, to: dst) }
        }

        let rotated = logsDir.appendingPathComponent("IconRulesAgent.log.1", isDirectory: false)
        if fm.fileExists(atPath: rotated.path) { try? fm.removeItem(at: rotated) }
        try? fm.moveItem(at: logFile, to: rotated)
    }
}
