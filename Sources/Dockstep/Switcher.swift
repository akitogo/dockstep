import AppKit
import Carbon.HIToolbox

/// One ⌘⇥ session: from the first Tab press until ⌘ is released.
///
/// While ⌘ is held, every key you press is ⌘+something, so the session keys
/// (⌘Tab, ⌘⇧Tab, ⌘←/→, ⌘1…⌘0, ⌘Q, ⌘H, ⌘Esc) are registered as global hotkeys
/// for the session and released again afterwards. ⌘ release is detected by
/// polling the modifier state, which needs no special permission.
final class Switcher {
    static let shared = Switcher()

    private let panel = SwitcherPanel()
    private var items: [SwitchItem] = []
    private var selected = 0
    private(set) var isActive = false

    private var triggerHotKeys: [UInt32] = []
    private var sessionHotKeys: [UInt32] = []
    private var modifierTimer: Timer?
    private var showPanelWork: DispatchWorkItem?

    /// How long ⌘ must stay down before the panel appears. A quick ⌘⇥ tap switches without flashing it.
    private let panelDelay: TimeInterval = 0.08

    private init() {
        panel.onHover = { [weak self] index in self?.setSelection(index) }
        panel.onClick = { [weak self] index in self?.commit(index: index) }
    }

    // MARK: - ⌘⇥ / ⌘⇧⇥ registration

    /// Returns false if the shortcuts could not be registered.
    @discardableResult
    func installTriggerHotKeys() -> Bool {
        guard triggerHotKeys.isEmpty else { return true }
        let forward = HotKeys.shared.register(keyCode: kVK_Tab, modifiers: cmdKey) { [weak self] in
            self?.trigger(step: 1)
        }
        let backward = HotKeys.shared.register(keyCode: kVK_Tab, modifiers: cmdKey | shiftKey) { [weak self] in
            self?.trigger(step: -1)
        }
        triggerHotKeys = [forward, backward].compactMap { $0 }
        if forward == nil {
            removeTriggerHotKeys()
            return false
        }
        return true
    }

    func removeTriggerHotKeys() {
        cancel()
        triggerHotKeys.forEach { HotKeys.shared.unregister($0) }
        triggerHotKeys.removeAll()
    }

    // MARK: - Session

    private func trigger(step: Int) {
        if isActive {
            move(step)
        } else {
            start(step: step)
        }
    }

    private func start(step: Int) {
        items = DockOrder.items(includeNotRunning: Settings.includeNotRunning)
        guard !items.isEmpty else { return }

        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let current = items.firstIndex { $0.app?.processIdentifier == frontPid }
        switch Settings.startPosition {
        case .nextAfterCurrent:
            if let current {
                selected = wrap(current + step)
            } else {
                selected = step > 0 ? 0 : items.count - 1
            }
        case .firstInDock:
            selected = step > 0 ? 0 : items.count - 1
        }

        isActive = true
        registerSessionHotKeys()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.checkCommandKey()
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.panel.show(items: self.items, selected: self.selected)
        }
        showPanelWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + panelDelay, execute: work)

        checkCommandKey()
    }

    private func checkCommandKey() {
        guard isActive else { return }
        if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
            commit(index: selected)
        }
    }

    private func move(_ step: Int) {
        setSelection(wrap(selected + step))
    }

    private func setSelection(_ index: Int) {
        guard isActive, items.indices.contains(index) else { return }
        selected = index
        panel.setSelection(index)
    }

    private func commit(index: Int) {
        guard isActive, items.indices.contains(index) else { return }
        let item = items[index]
        end()
        Activator.bringToFront(item)
    }

    func cancel() {
        guard isActive else { return }
        end()
    }

    private func end() {
        isActive = false
        modifierTimer?.invalidate()
        modifierTimer = nil
        showPanelWork?.cancel()
        showPanelWork = nil
        sessionHotKeys.forEach { HotKeys.shared.unregister($0) }
        sessionHotKeys.removeAll()
        panel.hide()
    }

    private func quitSelected() {
        guard isActive, items.indices.contains(selected) else { return }
        guard let app = items[selected].app else { return }
        app.terminate()
        items.remove(at: selected)
        if items.isEmpty { end(); return }
        selected = min(selected, items.count - 1)
        if panel.isVisible { panel.show(items: items, selected: selected) }
    }

    private func toggleHideSelected() {
        guard isActive, items.indices.contains(selected), let app = items[selected].app else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
    }

    private func wrap(_ index: Int) -> Int {
        let count = items.count
        return ((index % count) + count) % count
    }

    private func registerSessionHotKeys() {
        let keys = HotKeys.shared
        var ids: [UInt32?] = [
            keys.register(keyCode: kVK_Escape, modifiers: cmdKey) { [weak self] in self?.cancel() },
            keys.register(keyCode: kVK_Escape, modifiers: cmdKey | shiftKey) { [weak self] in self?.cancel() },
            keys.register(keyCode: kVK_LeftArrow, modifiers: cmdKey) { [weak self] in self?.move(-1) },
            keys.register(keyCode: kVK_RightArrow, modifiers: cmdKey) { [weak self] in self?.move(1) },
            keys.register(keyCode: kVK_Return, modifiers: cmdKey) { [weak self] in
                guard let self else { return }
                self.commit(index: self.selected)
            },
            keys.register(keyCode: kVK_ANSI_Q, modifiers: cmdKey) { [weak self] in self?.quitSelected() },
            keys.register(keyCode: kVK_ANSI_H, modifiers: cmdKey) { [weak self] in self?.toggleHideSelected() },
        ]
        // ⌘1 … ⌘9, ⌘0 jump straight to that position (unless position numbers are off).
        if Settings.numberPosition.shortcutsEnabled {
            let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                             kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
            for (position, keyCode) in digitKeys.enumerated() {
                ids.append(keys.register(keyCode: keyCode, modifiers: cmdKey) { [weak self] in
                    self?.commit(index: position)
                })
            }
        }
        sessionHotKeys = ids.compactMap { $0 }
    }
}

/// Brings an app to the front the way the built-in switcher does.
enum Activator {
    private static var generation = 0

    static func bringToFront(_ item: SwitchItem) {
        generation += 1
        let myGeneration = generation

        guard let app = item.app, !app.isTerminated else {
            open(item.bundleURL)
            return
        }
        if app.isHidden { app.unhide() }
        if app.isActive { return }
        app.activate(options: [])

        // If macOS ignored the request, fall back to what a Dock click does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard myGeneration == generation, !app.isTerminated, !app.isActive else { return }
            open(app.bundleURL)
        }
    }

    private static func open(_ url: URL?) {
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("Dockstep: could not open \(url.path): \(error.localizedDescription)") }
        }
    }
}
