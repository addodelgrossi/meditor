import Foundation

enum AppInfo {
    static let author = "Addo Del Grossi"
    static let sourceURL = URL(string: "https://github.com/addodelgrossi/meditor")!
    static let privacyURL = URL(string: "https://addodelgrossi.github.io/meditor/privacy/")!
    static let supportURL = URL(string: "https://addodelgrossi.github.io/meditor/support/")!

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
