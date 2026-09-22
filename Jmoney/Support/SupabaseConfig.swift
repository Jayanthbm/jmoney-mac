import Foundation

/// The Supabase connection settings.
///
/// The React Native app hardcodes the project URL and anon key in
/// `src/services/supabase.ts`. The macOS app must not do that (master prompt
/// §15), so the values come from build configuration instead: `Jmoney.xcconfig`
/// → `INFOPLIST_KEY_JMoneySupabase*` → Info.plist → here.
///
/// An unconfigured build is a **supported** state, not a crash: local-only use
/// works exactly as before and Settings says cloud sync is unavailable. That is
/// also what makes the app buildable in a fresh checkout, where the committed
/// `.xcconfig` template is empty by design.
struct SupabaseConfig: Equatable, Sendable {
    var url: URL
    var anonKey: String

    /// The Info.plist keys populated from the xcconfig.
    enum InfoKey {
        static let url = "JMoneySupabaseURL"
        static let anonKey = "JMoneySupabaseAnonKey"
    }

    /// Why cloud features are unavailable, so the UI can be specific.
    ///
    /// An `Error` so it can travel in a `Result`/`SyncError`; being unavailable is
    /// a configuration state, not a crash.
    enum Unavailable: Error, Equatable {
        /// One or both keys are missing or blank.
        case notConfigured
        /// A URL was supplied but cannot be parsed.
        case invalidURL(String)

        var message: String {
            switch self {
            case .notConfigured:
                return "Cloud sync is unavailable: no Supabase project is configured."
            case .invalidURL(let raw):
                return "Cloud sync is unavailable: “\(raw)” is not a valid Supabase URL."
            }
        }
    }

    // MARK: - Resolution

    /// Reads the configuration out of an Info.plist dictionary.
    ///
    /// Returns the reason it is unavailable rather than throwing, because the
    /// caller's job is to disable cloud features honestly, not to report a bug.
    static func resolve(info: [String: Any]?) -> Result<SupabaseConfig, Unavailable> {
        resolve(
            urlString: info?[InfoKey.url] as? String,
            anonKey: info?[InfoKey.anonKey] as? String
        )
    }

    /// The testable core: blank/absent values mean "not configured".
    static func resolve(urlString: String?, anonKey: String?) -> Result<SupabaseConfig, Unavailable> {
        let url = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = anonKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !key.isEmpty else { return .failure(.notConfigured) }
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
            return .failure(.invalidURL(url))
        }
        return .success(SupabaseConfig(url: parsed, anonKey: key))
    }

    /// The app's configuration, or why it is missing.
    static func resolve(bundle: Bundle = .main) -> Result<SupabaseConfig, Unavailable> {
        resolve(info: bundle.infoDictionary)
    }
}
