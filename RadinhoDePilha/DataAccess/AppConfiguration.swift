import Foundation

/// Access to build-time configuration values injected through xcconfig files.
///
/// The credentials live in `Config/Secrets.xcconfig`, which is not under version control. The
/// xcconfig promotes each to a build setting, `Config/Info.plist` expands it into the generated
/// property list, and this type reads it from the bundle at runtime. A credential therefore never
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

    /// Info.plist key holding the Sportmonks credential.
    static let sportmonksTokenName = "SportmonksToken"

    /// Credential for Sportmonks, or `nil` when it has not been provided.
    ///
    /// Travels the same route as the API-Football key, from `SPORTMONKS_TOKEN` in
    /// `Config/Secrets.xcconfig` through `Config/Info.plist`.
    static var sportmonksToken: String? {
        sanitizedKey(
            from: Bundle.main.object(forInfoDictionaryKey: sportmonksTokenName) as? String
        )
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
