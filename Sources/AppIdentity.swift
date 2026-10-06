import Foundation

/// Use the same preferences domain for the app bundle and direct CLI runs,
/// independent of executable name, architecture, or installation path.
enum AppIdentity {
    static let bundleID = "dev.abdus.kuller"

    static var preferences: UserDefaults {
        // A suite named after the running bundle is rejected by Foundation;
        // standard already uses that exact domain inside the app bundle.
        if Bundle.main.bundleIdentifier == bundleID { return .standard }
        return UserDefaults(suiteName: bundleID)!
    }
}
