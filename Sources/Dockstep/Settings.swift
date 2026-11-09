import Foundation

enum StartPosition: String {
    /// The first ⌘⇥ press selects the app to the right of the current one in the Dock.
    case nextAfterCurrent
    /// The first ⌘⇥ press always selects the first app in the Dock, so each app
    /// is always the same number of Tab presses away.
    case firstInDock
}

/// How the 1…0 position numbers are shown, and whether ⌘1…⌘0 jump to a position.
enum NumberPosition: String {
    /// A small "⌘3" badge on the icon's top-right corner. Takes no extra space.
    case badge
    /// A row of numbers above the icons.
    case top
    /// A row of numbers below the icons.
    case bottom
    /// Numbers not drawn, ⌘1…⌘0 still work.
    case hidden
    /// Numbers not drawn and ⌘1…⌘0 not used.
    case off

    var showsNumber: Bool { self == .badge || self == .top || self == .bottom }
    /// Top and bottom need their own row; the badge sits on the icon.
    var needsRow: Bool { self == .top || self == .bottom }
    var shortcutsEnabled: Bool { self != .off }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    static var startPosition: StartPosition {
        get { StartPosition(rawValue: defaults.string(forKey: "startPosition") ?? "") ?? .nextAfterCurrent }
        set { defaults.set(newValue.rawValue, forKey: "startPosition") }
    }

    static var includeNotRunning: Bool {
        get { defaults.bool(forKey: "includeNotRunning") }
        set { defaults.set(newValue, forKey: "includeNotRunning") }
    }

    static var numberPosition: NumberPosition {
        get {
            if let raw = defaults.string(forKey: "numberPosition"), let value = NumberPosition(rawValue: raw) {
                return value
            }
            // Earlier versions only had an on/off switch.
            return defaults.object(forKey: "showNumbers") as? Bool == false ? .hidden : .badge
        }
        set { defaults.set(newValue.rawValue, forKey: "numberPosition") }
    }

    static var didShowWelcome: Bool {
        get { defaults.bool(forKey: "didShowWelcome") }
        set { defaults.set(newValue, forKey: "didShowWelcome") }
    }
}
