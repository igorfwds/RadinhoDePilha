import Foundation

/// Provider that replays a finished match as if it were happening now.
///
/// Exists because the live loop cannot be exercised against static data: a provider that always
/// returns the same seven events gives the loop nothing to detect, and the app falls silent the
/// moment the listener presses play. Compressing match time against real time turns the sample
/// match into something that can actually be heard changing.
///
/// It is also the only way to hear the interruption policy work before the API credential exists.
/// Two events arriving within the same cycle is the situation priority was designed for, and it
/// cannot be produced by hand at the interface.
///
/// Deliberately not an `actor`: the simulated clock is derived from ``startedAt`` rather than
/// stored, so there is no mutable state to protect and the type stays as cheap to inject as the
/// static provider it stands in for.
nonisolated struct SimulatedLiveMatchProvider: MatchDataProvider {
    /// Match whose events are replayed.
    private let base: Match

    /// Simulated minute at the moment the provider was created.
    ///
    /// Starting mid-match is the case worth rehearsing: it is what happens when someone opens the
    /// app during the second half, and it is precisely the situation that exposed the ordering
    /// defect in the first place.
    private let startMinute: Int

    /// Real seconds that pass for each minute of match time.
    private let secondsPerMatchMinute: Double

    private let startedAt: Date

    init(
        base: Match,
        startMinute: Int = 60,
        secondsPerMatchMinute: Double = 3,
        startedAt: Date = Date()
    ) {
        self.base = base
        self.startMinute = startMinute
        self.secondsPerMatchMinute = secondsPerMatchMinute
        self.startedAt = startedAt
    }

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        let current = state(at: Date())

        guard current.competition == competition,
              current.season == season,
              current.isLive
        else { return [] }

        return [current]
    }

    func match(withID id: String) async throws -> Match {
        guard id == base.id else { throw MatchDataError.matchNotFound(id: id) }

        return state(at: Date())
    }

    // MARK: - Simulated clock

    /// The match as it stands at a given instant of real time.
    func state(at instant: Date) -> Match {
        let minute = simulatedMinute(at: instant)
        let revealed = base.events.filter { $0.minute <= minute }
        let status = status(atMinute: minute)

        return Match(
            id: base.id,
            competition: base.competition,
            season: base.season,
            homeTeam: base.homeTeam,
            awayTeam: base.awayTeam,
            kickoff: base.kickoff,
            status: status,
            elapsedMinutes: status.isLive ? min(minute, Self.fullTime) : nil,
            score: score(from: revealed),
            events: revealed
        )
    }

    private func simulatedMinute(at instant: Date) -> Int {
        let elapsed = instant.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return startMinute }

        return startMinute + Int(elapsed / secondsPerMatchMinute)
    }

    private static let halfTime = 45
    private static let fullTime = 90

    private func status(atMinute minute: Int) -> MatchStatus {
        switch minute {
        case ..<0: .scheduled
        case ...Self.halfTime: .firstHalf
        case ...Self.fullTime: .secondHalf
        default: .finished
        }
    }

    /// Score implied by the events revealed so far.
    ///
    /// Recomputed rather than taken from ``base``, whose score reflects the whole match. Reporting
    /// the final score alongside a partial event list would make the narration contradict itself.
    private func score(from events: [MatchEvent]) -> Score {
        var home = 0
        var away = 0

        for event in events {
            let scoredForHome: Bool

            switch event.kind {
            case .goal, .penaltyScored:
                scoredForHome = event.team.id == base.homeTeam.id
            case .ownGoal:
                scoredForHome = event.team.id != base.homeTeam.id
            default:
                continue
            }

            if scoredForHome { home += 1 } else { away += 1 }
        }

        return Score(home: home, away: away)
    }
}
