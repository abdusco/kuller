import Foundation

/// Use the same preferences domain for the app bundle and direct CLI runs,
/// independent of executable name, architecture, or installation path.
enum AppIdentity {
    static let bundleID = "dev.abdus.kuller"
}
