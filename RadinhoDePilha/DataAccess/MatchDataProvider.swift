import Foundation

/// Source of match data, whatever it happens to be.
///
/// This is the seam the rest of the app is written against. Nothing above this protocol knows
/// whether the data came from API-Football, from a competing vendor, or from a JSON file on
/// disk. Adding a provider means writing one conforming type; it does not mean touching the
/// domain, the narration engine, the views, or their tests.
///
/// The protocol is deliberately narrow. Every method declared here has to be implemented by
/// every adapter and every test double, so it states what the app genuinely needs and nothing
/// more.
///
/// Note that the contract says nothing about how many network requests an implementation
/// makes. ``match(withID:)`` returns a fully populated ``Match`` including its events; whether
/// that costs one HTTP call or three is the adapter's problem, not the caller's.
///
/// `Sendable` conformance is required because implementations are injected into view models
/// and polling tasks that cross concurrency domains.
nonisolated protocol MatchDataProvider: Sendable {
    /// Matches currently under way in the given competition and season.
    ///
    /// Returns an empty array when nothing is being played, which is the common case outside
    /// match days and is not an error.
    ///
    /// - Throws: ``MatchDataError``.
    func liveMatches(competition: Competition, season: Int) async throws -> [Match]

    /// Full current state of a single match, including every event known so far.
    ///
    /// This is the call the polling loop repeats while a match is live. Implementations should
    /// return the complete event list rather than a delta: deciding what is new is the
    /// caller's job, and it needs the full picture to do it reliably.
    ///
    /// - Throws: ``MatchDataError``.
    func match(withID id: String) async throws -> Match
}
