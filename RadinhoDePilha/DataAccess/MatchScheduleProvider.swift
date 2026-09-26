import Foundation

/// A team's fixture list around the present: the last match played and the next one scheduled.
///
/// Separate from ``MatchDataProvider`` because it answers a different question. That contract is
/// about following a match; this one is about what to show when there is no match to follow. Not
/// every source can answer it (recorded fixtures cannot), and keeping it apart means those sources
/// are not forced to pretend.
///
/// Team identifiers are the domain's `String`, as everywhere above the adapters. Converting to the
/// vendor's own numbering is the adapter's business, which is what lets the presentation layer ask
/// for Náutico's next match without knowing how any vendor numbers it.
nonisolated protocol MatchScheduleProvider: Sendable {
    /// The most recent match the team played, or `nil` when the provider has none.
    ///
    /// - Throws: ``MatchDataError``.
    func lastMatch(forTeam teamID: String) async throws -> Match?

    /// The team's next scheduled match, or `nil` when nothing is scheduled.
    ///
    /// Returning `nil` is a normal outcome: seasons end.
    ///
    /// - Throws: ``MatchDataError``.
    func nextMatch(forTeam teamID: String) async throws -> Match?
}
