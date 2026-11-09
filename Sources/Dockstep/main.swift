import AppKit

let arguments = CommandLine.arguments

// `Dockstep --restore-cmd-tab`: turn the built-in switcher back on (e.g. after `kill -9`).
if arguments.contains("--version") {
    print("Dockstep \(AppInfo.version) (build \(AppInfo.build))")
    exit(0)
}

if arguments.contains("--restore-cmd-tab") {
    NativeCommandTab.setEnabled(true)
    print("Built-in ⌘⇥ is \(NativeCommandTab.isEnabled ? "on" : "still off")")
    exit(0)
}

// `Dockstep --print-order`: list the apps in the order ⌘⇥ will show them.
if arguments.contains("--print-order") {
    for (index, item) in DockOrder.items(includeNotRunning: arguments.contains("--all")).enumerated() {
        let state = !item.isRunning ? "not running" : (item.isPinned ? "in Dock" : "running")
        print(String(format: "%2d  %@  (%@)", index + 1, item.name, state))
    }
    exit(0)
}

// `Dockstep --snapshot out.png [--dark] [--numbers badge|top|bottom|hidden|off] [--demo] [--framed]`:
// render the panel to a PNG. --demo uses standard Apple apps instead of yours, --framed adds a
// transparent margin with a drop shadow (for the README).
if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
    _ = NSApplication.shared
    let items = arguments.contains("--demo")
        ? DockOrder.demoItems()
        : DockOrder.items(includeNotRunning: arguments.contains("--all"))
    let width = (NSScreen.main?.visibleFrame.width ?? 1440) * 0.92
    let selected = min(2, max(items.count - 1, 0))
    var numbers = Settings.numberPosition
    if let n = arguments.firstIndex(of: "--numbers"), arguments.indices.contains(n + 1),
       let position = NumberPosition(rawValue: arguments[n + 1]) {
        numbers = position
    }
    guard let png = SwitcherPanel.snapshot(items: items, selected: selected, maxWidth: width,
                                           numberPosition: numbers, dark: arguments.contains("--dark"),
                                           framed: arguments.contains("--framed")) else {
        print("snapshot failed")
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}

// `Dockstep --print-menu`: print the menu bar menu as text (to check translations).
if arguments.contains("--print-menu") {
    let menuOwner = AppDelegate() // menu items point back at it, so keep it alive while printing
    withExtendedLifetime(menuOwner) { menuOwner.printMenu() }
    exit(0)
}

// Only one copy may own ⌘⇥.
if let bundleId = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).count > 1 {
    exit(0)
}

CrashGuard.install()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
