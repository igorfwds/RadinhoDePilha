import Foundation

/// State of a match at the time of the query.
nonisolated enum MatchStatus: String, Hashable, Sendable, CaseIterable {
    case scheduled
    case firstHalf
    case halfTime
    case secondHalf
    case extraTime

    /// Interval before or during extra time.
    case breakTime

    case penaltyShootout

    /// Under way, but the provider cannot say which period or minute.
    ///
    /// Rare, and the provider documents it as such. Distinct from ``unknown`` because the match
    /// *is* being played: treating it as an unknown state would stop polling on a live match, which
    /// is the worst possible moment to stop.
    case inProgress

    /// Halted by the referee and expected to resume in a few minutes.
    case interrupted

    /// Halted by the referee, possibly to be replayed another day.
    case suspended

    case finished

    /// Abandoned before the end, for weather, safety or lack of officials.
    case abandoned

    /// Decided off the pitch: a technical loss or a walkover.
    ///
    /// Kept apart from ``cancelled`` because the match has a result, even though it was not played
    /// to completion.
    case awarded

    case postponed
    case cancelled
    case unknown

    /// Whether the app should keep polling.
    ///
    /// Broader than "the ball is rolling": a suspended or interrupted match has not ended, and the
    /// listener needs to be told when it resumes. Stopping the loop would leave them waiting on
    /// news that never comes.
    var isLive: Bool {
        switch self {
        case .firstHalf, .halfTime, .secondHalf, .extraTime, .breakTime,
             .penaltyShootout, .inProgress, .interrupted, .suspended:
            true
        case .scheduled, .finished, .abandoned, .awarded, .postponed, .cancelled, .unknown:
            false
        }
    }

    /// Whether play is actually happening, as opposed to the match merely being open.
    ///
    /// Used where the distinction matters to the narration: an interrupted match should not be
    /// described as being in its second half.
    var isBallInPlay: Bool {
        switch self {
        case .firstHalf, .secondHalf, .extraTime, .penaltyShootout, .inProgress:
            true
        default:
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
