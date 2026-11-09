import AppKit

/// Makes sure the built-in ⌘⇥ comes back however Dockstep ends:
/// a normal quit (AppDelegate), being killed with SIGTERM/SIGINT/SIGHUP
/// (Activity Monitor, `kill`, closing a terminal) or crashing.
/// Only SIGKILL (`kill -9`) can't be caught; run `Dockstep --restore-cmd-tab` after that.
enum CrashGuard {
    private static var signalSources: [DispatchSourceSignal] = []

    static func install() {
        // Resolve the private function pointers now, never inside a signal handler.
        _ = NativeCommandTab.isAvailable

        let terminationSignals = [SIGTERM, SIGINT, SIGHUP]
        var mask = sigset_t()
        sigemptyset(&mask)
        for sig in terminationSignals {
            signal(sig, SIG_IGN)
            sigaddset(&mask, sig)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: DispatchQueue(label: "Dockstep.signals"))
            source.setEventHandler {
                NativeCommandTab.setEnabled(true)
                _exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        // A launcher can hand us a blocked signal mask; blocked signals would never arrive.
        pthread_sigmask(SIG_UNBLOCK, &mask, nil)

        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { received in
                NativeCommandTab.setEnabled(true)
                // Let the crash continue normally so macOS still writes a crash report.
                signal(received, SIG_DFL)
                raise(received)
            }
        }

        NSSetUncaughtExceptionHandler { _ in
            NativeCommandTab.setEnabled(true)
        }
    }
}
