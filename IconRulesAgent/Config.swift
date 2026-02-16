import Foundation

struct AppIconConfig: Equatable {
    var watchDir: URL
    /// Always includes /Applications. Optionally includes ~/Applications (toggle via config).
    var includeUserApplications: Bool
    var debounceMilliseconds: Int

    var applicationSearchDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs: [URL] = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if includeUserApplications {
            dirs.append(home.appendingPathComponent("Applications", isDirectory: true))
        }
        return dirs
    }

    static func defaultConfig() -> AppIconConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppIconConfig(
            watchDir: home.appendingPathComponent(".icons/icons", isDirectory: true),
            includeUserApplications: true,
            debounceMilliseconds: 350
        )
    }

    static func load(from path: URL) -> AppIconConfig {
        var cfg = AppIconConfig.defaultConfig()

        guard let data = try? Data(contentsOf: path),
              let text = String(data: data, encoding: .utf8)
        else {
            return cfg
        }

        func parseBool(_ s: String) -> Bool {
            ["1", "true", "yes", "on"].contains(
                s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }

            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "watch_dir":
                cfg.watchDir = URL(fileURLWithPath: (val as NSString).expandingTildeInPath, isDirectory: true)
            case "include_user_applications":
                cfg.includeUserApplications = parseBool(val)
            case "debounce_ms":
                if let ms = Int(val) { cfg.debounceMilliseconds = max(0, ms) }
            default:
                continue
            }
        }

        return cfg
    }
}
