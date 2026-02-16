import AppKit
import Foundation
import CoreServices
import Darwin

final class IconApplier {
    private let fm = FileManager.default
    private let log = Logger.shared

    // Tracks last applied icon file modification date per target path to avoid redundant sets
    private var lastAppliedIconModDate: [String: Date] = [:]

    // Prevent overlapping icon applications per target
    private var applyingTargets: Set<String> = []

    // Debug instrumentation toggle
    private let debugIconApply = true

    private func modificationDate(of url: URL) -> Date? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }

    func pickDefaultIconFile(in dir: URL) -> URL? {
        let icns = dir.appendingPathComponent("default.icns")
        if fm.fileExists(atPath: icns.path) { return icns }

        let png = dir.appendingPathComponent("default.png")
        if fm.fileExists(atPath: png.path) { return png }

        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let defaults = items.filter { $0.lastPathComponent.hasPrefix("default.") }
        return defaults.first
    }

    func applyRules(config: AppIconConfig, changedPath: URL?) {
        if let changedPath, changedPath.path.hasPrefix(config.watchDir.path + "/") {
            let rel = changedPath.path.dropFirst((config.watchDir.path + "/").count)
            let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
            if let ruleFolder = parts.first.map(String.init) {
                applyFor(ruleFolderName: ruleFolder, config: config)
                return
            }
        }

        guard let ruleDirs = try? fm.contentsOfDirectory(at: config.watchDir,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])
        else { return }

        for d in ruleDirs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue {
                applyFor(ruleFolderName: d.lastPathComponent, config: config)
            }
        }
    }

    func applyForAppBundleChange(config: AppIconConfig, appBundlePath: URL) {
        guard appBundlePath.pathExtension.lowercased() == "app" else { return }
        let name = appBundlePath.deletingPathExtension().lastPathComponent
        applyFor(ruleFolderName: name, config: config)
    }

    private func readTargets(from ruleDir: URL) -> [URL] {
        let ruleConf = ruleDir.appendingPathComponent("rule.conf", isDirectory: false)
        guard let data = try? Data(contentsOf: ruleConf),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var targets: [URL] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }

            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)

            guard key == "target" else { continue }
            let expanded = (val as NSString).expandingTildeInPath
            targets.append(URL(fileURLWithPath: expanded, isDirectory: true))
        }

        return targets
    }

    private func applyFor(ruleFolderName: String, config: AppIconConfig) {
        let ruleDir = config.watchDir.appendingPathComponent(ruleFolderName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: ruleDir.path, isDirectory: &isDir), isDir.boolValue else { return }

        let iconFile = pickDefaultIconFile(in: ruleDir)

        var targets = readTargets(from: ruleDir)
        if targets.isEmpty {
            for appsDir in config.applicationSearchDirs {
                let appPath = appsDir.appendingPathComponent("\(ruleFolderName).app", isDirectory: true)
                if fm.fileExists(atPath: appPath.path) {
                    targets.append(appPath)
                }
            }
        }

        guard !targets.isEmpty else {
            log.info("No targets for rule folder '\(ruleFolderName)' (app not found).")
            return
        }

        for target in targets where fm.fileExists(atPath: target.path) {
            // Debounce/serialize per-target icon application
            if applyingTargets.contains(target.path) {
                log.info("Debounce: icon application already in progress for \(target.path)")
                continue
            }
            applyingTargets.insert(target.path)
            defer { applyingTargets.remove(target.path) }

            // Check current custom icon state (fallback: look for Finder icon file inside bundle)
            let hasCustomIcon: Bool = hasCustomIconSet(at: target)

            if let iconFile {
                if debugIconApply {
                    let srcSize = fileSize(at: iconFile) ?? -1
                    log.info("Icon source: \(iconFile.path) size=\(srcSize) bytes")
                }

                // If there's no custom icon currently set, ensure we don't skip due to stale cache
                if hasCustomIcon == false {
                    lastAppliedIconModDate.removeValue(forKey: target.path)
                }

                let modDate = modificationDate(of: iconFile)
                if let modDate, let last = lastAppliedIconModDate[target.path], last == modDate, hasCustomIcon {
                    log.info("Skipping set icon for \(target.path) — already applied for icon mtime=\(modDate)")
                    continue
                }

                guard let img = makeIconImage(from: iconFile) else {
                    if debugIconApply {
                        log.info("Prepared icon image: reps=0 sizes=[]")
                    }
                    log.warn("Could not prepare icon image at \(iconFile.path)")
                    continue
                }
                if debugIconApply {
                    let repCount = img.representations.count
                    let repDescs = img.representations.map { rep -> String in
                        let s = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                        return "\(s.width)x\(s.height)"
                    }.joined(separator: ",")
                    log.info("Prepared icon image: reps=\(repCount) sizes=[\(repDescs)]")
                }
                // For app bundles, remove any existing Finder icon file to avoid stale cache reuse
                if target.pathExtension.lowercased() == "app" {
                    let iconCRName = "Icon\u{000D}"
                    let iconCRURL = target.appendingPathComponent(iconCRName, isDirectory: false)
                    if debugIconApply {
                        let exists = fm.fileExists(atPath: iconCRURL.path)
                        let fsize = fileSize(at: iconCRURL) ?? -1
                        let rsize = resourceForkSize(at: iconCRURL) ?? -1
                        log.info("Before set: IconCR exists=\(exists) fileSize=\(fsize) rsrc=\(rsize)")
                    }
                    // Selective cleanup: only remove if resource fork is missing or clearly invalid
                    if fm.fileExists(atPath: iconCRURL.path) {
                        let rsize = resourceForkSize(at: iconCRURL) ?? -1
                        if rsize <= 0 {
                            do { try fm.removeItem(at: iconCRURL); if debugIconApply { log.info("Removed broken IconCR before set") } } catch {
                                log.warn("Failed to remove stale Finder icon at \(iconCRURL.path): \(error.localizedDescription)")
                            }
                        }
                    }
                }
                if debugIconApply {
                    // Optional small delay to test for race conditions with Finder/LS
                    usleep(300_000) // 300ms
                }
                NSWorkspace.shared.setIcon(img, forFile: target.path, options: [])
                // Nudge Finder by updating the modification date on the bundle
                do {
                    try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
                } catch {
                    log.warn("Failed to update modification date for \(target.path): \(error.localizedDescription)")
                }
                if debugIconApply, target.pathExtension.lowercased() == "app" {
                    let iconCRName = "Icon\u{000D}"
                    let iconCRURL = target.appendingPathComponent(iconCRName, isDirectory: false)
                    let exists = fm.fileExists(atPath: iconCRURL.path)
                    let fsize = fileSize(at: iconCRURL) ?? -1
                    let rsize = resourceForkSize(at: iconCRURL) ?? -1
                    log.info("After set: IconCR exists=\(exists) fileSize=\(fsize) rsrc=\(rsize)")
                }
                // Verify that IconCR's resource fork is present; retry once if needed
                var verified = true
                if target.pathExtension.lowercased() == "app" {
                    let iconCRName = "Icon\u{000D}"
                    let iconCRURL = target.appendingPathComponent(iconCRName, isDirectory: false)
                    verified = verifyIconResourceWritten(at: iconCRURL)
                    if !verified {
                        if debugIconApply { log.warn("Icon resource not present after set; retrying once") }
                        // Retry once after a short delay
                        usleep(300_000)
                        NSWorkspace.shared.setIcon(img, forFile: target.path, options: [])
                        _ = try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
                        verified = verifyIconResourceWritten(at: iconCRURL)
                        if debugIconApply {
                            log.info("Retry result: verified=\(verified)")
                        }
                    }
                }
                // Ask Launch Services and Finder to refresh their caches for this item
                refreshSystemIconCaches(for: target)
                if let modDate { lastAppliedIconModDate[target.path] = modDate }
                log.info("Set icon for \(target.path) using \(iconFile.lastPathComponent)")
            } else {
                // Only remove if a custom icon is currently set
                if hasCustomIcon {
                    NSWorkspace.shared.setIcon(nil, forFile: target.path, options: [])
                    lastAppliedIconModDate.removeValue(forKey: target.path)
                    log.info("Removed custom icon for \(target.path)")
                } else {
                    log.info("Skipping remove for \(target.path) — no custom icon present")
                }
            }
        }
    }

    // Fallback detector for custom icons without relying on URLResourceKey.hasCustomIconKey (not available in some SDKs)
    private func hasCustomIconSet(at url: URL) -> Bool {
        // For app bundles, Finder stores a custom icon as a file named "Icon\r" at the root of the bundle
        // (0x0D carriage return). We'll check for that sentinel.
        if url.pathExtension.lowercased() == "app" {
            let iconCarriageReturnName = "Icon\u{000D}"
            let finderIconURL = url.appendingPathComponent(iconCarriageReturnName, isDirectory: false)
            if fm.fileExists(atPath: finderIconURL.path) {
                return true
            }
        }
        // For other directories/files, we conservatively return false. This avoids compile errors
        // on platforms where hasCustomIconKey is unavailable while keeping behavior predictable.
        return false
    }

    // Builds an NSImage with standard icon representations (16–1024) from a source image file
    private func makeIconImage(from url: URL) -> NSImage? {
        guard let baseImage = NSImage(contentsOf: url) else { return nil }
        baseImage.isTemplate = false
        // If the image already has multiple reps (e.g., from an ICNS), just return it
        if baseImage.representations.count > 1 {
            return baseImage
        }

        // Generate common icon sizes
        let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
        let icon = NSImage(size: NSSize(width: 1024, height: 1024))
        icon.isTemplate = false

        for side in sizes {
            let size = NSSize(width: side, height: side)
            if let rep = rasterize(image: baseImage, to: size) {
                icon.addRepresentation(rep)
            }
        }

        // Fallback: ensure at least one representation exists
        if icon.representations.isEmpty, let rep = rasterize(image: baseImage, to: baseImage.size) {
            icon.addRepresentation(rep)
        }

        return icon
    }

    // Rasterizes an NSImage to a bitmap representation at the given size
    private func rasterize(image: NSImage, to size: NSSize) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width),
                                   pixelsHigh: Int(size.height),
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0,
                                   bitsPerPixel: 0)
        guard let rep else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.cgContext.interpolationQuality = .high
            let rect = NSRect(origin: .zero, size: size)
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    private func refreshSystemIconCaches(for url: URL) {
        // Launch Services refresh: re-register the app/file URL to update icon cache
        let cfURL = url as CFURL
        let status = LSRegisterURL(cfURL, true)
        if status != noErr {
            log.warn("LSRegisterURL failed for \(url.path) with status: \(status)")
        }
        // Notify workspace of filesystem change (legacy but still useful for Finder refresh)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }

    private func fileSize(at url: URL) -> Int64? {
        if let attrs = try? fm.attributesOfItem(atPath: url.path), let sz = attrs[.size] as? NSNumber {
            return sz.int64Value
        }
        return nil
    }
    private func resourceForkSize(at url: URL) -> Int64? {
        // Read the com.apple.ResourceFork xattr length if present
        let path = (url.path as NSString)
        let name = "com.apple.ResourceFork"
        let bufSize = getxattr(path.fileSystemRepresentation, name, nil, 0, 0, 0)
        if bufSize > 0 { return Int64(bufSize) }
        return nil
    }

    // Verify IconCR has a non-zero resource fork, with brief retries
    private func verifyIconResourceWritten(at iconCRURL: URL) -> Bool {
        let attempts = 3
        for i in 0..<attempts {
            let exists = fm.fileExists(atPath: iconCRURL.path)
            let rsize = resourceForkSize(at: iconCRURL) ?? -1
            let fsize = fileSize(at: iconCRURL) ?? -1
            if debugIconApply {
                log.info("Verify[\(i)]: exists=\(exists) fileSize=\(fsize) rsrc=\(rsize)")
            }
            if exists && rsize > 0 { return true }
            usleep(150_000) // wait 150ms then check again
        }
        return false
    }
}

