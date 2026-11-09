import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var watchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NativeCommandTab.isAvailable else {
            showAlert(L("Dockstep can't run on this macOS version"),
                      L("The system function for turning off the built-in ⌘⇥ switcher was not found."))
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        applyEnabled()

        // Another app (or a crashed earlier Dockstep session) may turn the built-in switcher back on.
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            if Settings.enabled && NativeCommandTab.isEnabled { NativeCommandTab.setEnabled(false) }
        }

        if !Settings.didShowWelcome {
            Settings.didShowWelcome = true
            showAlert(L("Dockstep is running"),
                      L("⌘⇥ now goes through your apps in Dock order.\n\nWhile holding ⌘: Tab / ⇧Tab or ←/→ to move, 1…9 and 0 to jump to a position, Q to quit and H to hide the selected app, Esc to cancel.\n\nSettings are in the menu bar icon."))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Switcher.shared.removeTriggerHotKeys()
        NativeCommandTab.setEnabled(true)
    }

    // MARK: - Enabling

    private func applyEnabled() {
        if Settings.enabled {
            NativeCommandTab.setEnabled(false)
            if !Switcher.shared.installTriggerHotKeys() {
                NativeCommandTab.setEnabled(true)
                Settings.enabled = false
                showAlert(L("⌘⇥ is already in use"),
                          L("Another app (for example AltTab) has taken ⌘⇥. Quit it and turn Dockstep on again."))
            }
        } else {
            Switcher.shared.removeTriggerHotKeys()
            NativeCommandTab.setEnabled(true)
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header(L("Dockstep: ⌘⇥ in Dock order")))
        menu.addItem(item(L("Use Dock order for ⌘⇥"), #selector(toggleEnabled), on: Settings.enabled))
        menu.addItem(.separator())

        menu.addItem(header(L("First ⌘⇥ press selects")))
        menu.addItem(option(L("The next app after the current one"), #selector(startNext),
                            on: Settings.startPosition == .nextAfterCurrent))
        menu.addItem(option(L("The first app in the Dock (fixed positions)"), #selector(startFirst),
                            on: Settings.startPosition == .firstInDock))
        menu.addItem(.separator())

        menu.addItem(header(L("Position numbers (⌘1…⌘0)")))
        let positions: [(String, Selector, NumberPosition)] = [
            (L("Badge on the icon (top right)"), #selector(numbersBadge), .badge),
            (L("Above the icons"), #selector(numbersTop), .top),
            (L("Below the icons"), #selector(numbersBottom), .bottom),
            (L("Hidden (⌘1…⌘0 still work)"), #selector(numbersHidden), .hidden),
            (L("Off (⌘1…⌘0 turned off too)"), #selector(numbersOff), .off),
        ]
        for (title, action, position) in positions {
            menu.addItem(option(title, action, on: Settings.numberPosition == position))
        }
        menu.addItem(.separator())

        menu.addItem(item(L("Also show Dock apps that aren't running"), #selector(toggleNotRunning),
                          on: Settings.includeNotRunning))
        menu.addItem(.separator())

        menu.addItem(item(loginItemTitle(), #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit Dockstep (restores normal ⌘⇥)"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Prints the menu as text (used by `Dockstep --print-menu` to check the translations).
    func printMenu() {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        for item in menu.items {
            if item.isSeparatorItem { print("  ────"); continue }
            let mark = item.state == .on ? "✓" : " "
            print("\(mark) \(String(repeating: "    ", count: item.indentationLevel))\(item.title)")
        }
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func option(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let option = item(title, action, on: on)
        option.indentationLevel = 1
        return option
    }

    private func loginItemTitle() -> String {
        SMAppService.mainApp.status == .requiresApproval
            ? L("Open at Login (allow in System Settings › General › Login Items)")
            : L("Open at Login")
    }

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        applyEnabled()
    }

    @objc private func startNext() { Settings.startPosition = .nextAfterCurrent }
    @objc private func startFirst() { Settings.startPosition = .firstInDock }
    @objc private func toggleNotRunning() { Settings.includeNotRunning.toggle() }
    @objc private func numbersBadge() { Settings.numberPosition = .badge }
    @objc private func numbersTop() { Settings.numberPosition = .top }
    @objc private func numbersBottom() { Settings.numberPosition = .bottom }
    @objc private func numbersHidden() { Settings.numberPosition = .hidden }
    @objc private func numbersOff() { Settings.numberPosition = .off }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert(L("Couldn't change Open at Login"), error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
