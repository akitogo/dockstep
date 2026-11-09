import Foundation

enum AppInfo {
    /// The marketing version, e.g. "1.0.0". build.sh stamps it from the VERSION file.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The build number (git commit count at build time).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static let website = URL(string: "https://github.com/akitogo/dockstep")!
}
