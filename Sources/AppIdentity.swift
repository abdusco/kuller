import Foundation

/// This binary isn't packaged as a real .app bundle (no Info.plist), so
/// `Bundle.main.bundleIdentifier` is nil at runtime and `UserDefaults.standard`
/// would fall back to a domain derived from the process name — which changes
/// with `build.sh`'s per-arch binary name (`kuller-arm64` vs `kuller-x86_64`).
/// Anything that needs a stable preferences domain should use
/// `UserDefaults(suiteName: AppIdentity.bundleID)` instead of `.standard`.
enum AppIdentity {
    static let bundleID = "dev.abdus.kuller"
}
