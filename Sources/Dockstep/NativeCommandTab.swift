import Foundation

/// Turns the system's own ⌘⇥ / ⌘⇧⇥ app switcher off and on.
///
/// macOS has no public API for this. WindowServer exposes the private
/// `CGSSetSymbolicHotKeyEnabled`, which every Cmd+Tab replacement relies on.
/// The functions are looked up at runtime so a missing symbol never crashes the app.
///
/// Important: the change outlives this process. If Dockstep stops without
/// re-enabling, the built-in switcher stays off until something turns it back on
/// (Dockstep does that on quit, on crash signals, and via `Dockstep --restore-cmd-tab`).
enum NativeCommandTab {
    private typealias SetEnabledFn = @convention(c) (UInt32, Bool) -> Int32
    private typealias IsEnabledFn = @convention(c) (UInt32) -> Bool

    /// Symbolic hotkey ids: 1 = ⌘⇥ (next app), 2 = ⌘⇧⇥ (previous app).
    private static let hotKeyIds: [UInt32] = [1, 2]

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static let setEnabledFn: SetEnabledFn? = {
        guard let sym = dlsym(rtldDefault, "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: SetEnabledFn.self)
    }()

    private static let isEnabledFn: IsEnabledFn? = {
        guard let sym = dlsym(rtldDefault, "CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: IsEnabledFn.self)
    }()

    /// Also forces the lazy lookups, so signal handlers never have to run them.
    static var isAvailable: Bool { setEnabledFn != nil && isEnabledFn != nil }

    static var isEnabled: Bool { isEnabledFn?(hotKeyIds[0]) ?? true }

    static func setEnabled(_ enabled: Bool) {
        guard let setEnabledFn else { return }
        for id in hotKeyIds { _ = setEnabledFn(id, enabled) }
    }
}
