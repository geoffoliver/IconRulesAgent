# IconRulesAgent

IconRulesAgent is a lightweight macOS menu bar utility that watches a directory of per‑app icon rules and applies custom icons to your apps. It runs without a Dock icon and provides a status bar menu plus a drag‑and‑drop window to quickly add apps.

## Highlights
- Menu bar app (no Dock icon)
- Watches a configurable rules directory (`watch_dir`)
- Applies per‑app custom icons automatically
- Drag‑and‑drop window to add `.app` bundles
- Handy menu actions: Open Rules, Open Logs, Reload & Reapply, Quit

## How it works
At a high level:
1. On launch, the app loads (or creates) a config file at `~/.icons/config.conf` and ensures the configured `watch_dir` exists.
2. A file system watcher observes `watch_dir` and relevant application folders for changes.
3. For each rule folder inside `watch_dir`, the app:
   - Reads `rule.conf` for one or more `target=` lines that point to app bundles.
   - Picks an icon image (e.g., `default.icns`, `default.png`, or any `default.*`).
   - Sets that image as the bundle’s custom icon and nudges Finder/Launch Services to refresh.
4. A drag‑and‑drop window lets you drop `.app` bundles to create/update rule folders and their `rule.conf` entries.

## Installation & running
- Open the project in Xcode (macOS target) and build/run.
- On first launch, the app:
  - Hides its Dock icon (accessory activation policy).
  - Creates default configuration and directories if they don’t exist.
  - Shows a menu bar item you can click for actions.

## Using the menu bar
Click the menu bar icon to open the app menu:
- Add App… (⌘D)
  - Opens the “Drop Your App Here” window. Drag one or more `.app` bundles into the window to add them as targets.
- Open Rules Folder (⌘O)
  - Opens the configured `watch_dir` in Finder.
- Open Logs Folder (⌘L)
  - Opens the app’s log directory in Finder.
- Reload Config & Reapply (⌘R)
  - Reloads configuration and reapplies icons across all rules.
- Quit (⌘Q)
  - Exits the app.

## The drop window
- Title: “Drop Your App Here”.
- Drag one or more `.app` bundles into the window.
- The app will:
  1) Create (or reuse) a rule folder named after the app (e.g., `MyApp`).
  2) Ensure a `rule.conf` exists and add a `target=/path/to/MyApp.app` line if missing.
  3) Open the rule folder in Finder so you can place an icon file.

## Rules directory layout
- `watch_dir/` — the base directory for rules
  - `MyApp/` — a folder per target app
    - `default.icns` or `default.png` — icon to apply (any `default.*` image works)
    - `rule.conf` — text file with one or more `target=` entries

Example `rule.conf`:

