import Foundation

/// Access to build-time configuration values injected through xcconfig files.
///
/// The API key lives in `Config/Secrets.xcconfig`, which is not under version control. The
/// xcconfig promotes it to a build setting, `Config/Info.plist` expands it into the generated
/// property list, and this type reads it from the bundle at runtime. The key therefore never
/// appears in source, in git history, or on screen while presenting the code.
nonisolated enum AppConfiguration {
    /// Info.plist key holding the API-Football credential.
    static let apiFootballKeyName = "APIFootballKey"

    /// Placeholder shipped in the committed template, treated as "not configured yet".
    static let keyPlaceholder = "sua_chave_aqui"

    /// Credential for API-Football, or `nil` when it has not been provided.
    static var apiFootballKey: String? {
        sanitizedKey(
            from: Bundle.main.object(forInfoDictionaryKey: apiFootballKeyName) as? String
        )
    }

    /// Whether the app has enough configuration to talk to API-Football.
    ///
    /// Lets composition choose between the live provider and the local fixture provider
    /// without every call site repeating the check.
    static var hasAPIFootballKey: Bool {
        apiFootballKey != nil
    }

    /// Normalises a raw configuration value into a usable credential, or `nil`.
    ///
    /// Split out from ``apiFootballKey`` so the rules can be tested without depending on the
    /// bundle: a test asserting against `Bundle.main` would pass today and start failing the
    /// day a real key is pasted in, which is the worst possible moment for a test to break.
    ///
    /// Returning `nil` instead of an empty string is deliberate. An empty string would satisfy
    /// the type system, travel all the way to the network layer, and come back as an opaque
    /// HTTP 401 with no hint that the cause was a missing local file.
    static func sanitizedKey(from raw: String?) -> String? {
        guard let raw else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != keyPlaceholder else { return nil }

        return trimmed
    }
}
