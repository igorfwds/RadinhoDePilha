import Foundation

/// State of a match at the time of the query.
nonisolated enum MatchStatus: String, Hashable, Sendable, CaseIterable {
    case scheduled
    case firstHalf
    case halfTime
    case secondHalf
    case extraTime
    case penaltyShootout
    case finished
    case postponed
    case cancelled
    case unknown

    /// Whether the match is under way, which decides if polling should keep running.
    var isLive: Bool {
        switch self {
        case .firstHalf, .halfTime, .secondHalf, .extraTime, .penaltyShootout:
            true
        case .scheduled, .finished, .postponed, .cancelled, .unknown:
            false
        }
    }
}

/// Match scoreline.
nonisolated struct Score: Hashable, Sendable {
    let home: Int
    let away: Int

    static let goalless = Score(home: 0, away: 0)
}

/// A football match and its current state.
nonisolated struct Match: Identifiable, Hashable, Sendable {
    /// Stable identifier of the match in the data source.
    let id: String

    /// Competition the match belongs to.
    let competition: Competition

    /// Season year. E.g. 2026.
    ///
    /// Kept apart from ``competition`` because the 2026 and 2027 editions of Série B are the
    /// same competition in different seasons, which is how providers model it.
    let season: Int
    let homeTeam: Team
    let awayTeam: Team

    /// Scheduled kick-off time.
    let kickoff: Date

    let status: MatchStatus

    /// Minutes elapsed, when the match is under way.
    ///
    /// Kept apart from ``status`` because providers deliver the two independently, and not
    /// every state carries a minute.
    let elapsedMinutes: Int?

    let score: Score

    /// Occurrences known so far, in chronological order.
    let events: [MatchEvent]

    var isLive: Bool { status.isLive }

    /// Resolves one of the two competing teams by identifier.
    ///
    /// Lets the narration engine add context without carrying extra references around.
    func team(withID id: String) -> Team? {
        switch id {
        case homeTeam.id: homeTeam
        case awayTeam.id: awayTeam
        default: nil
        }
    }
}
