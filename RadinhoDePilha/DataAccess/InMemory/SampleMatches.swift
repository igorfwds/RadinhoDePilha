import Foundation

/// Hand-built match data for development, previews and tests.
///
/// Player names are fictional. The point of this data is to exercise narration paths — an
/// equaliser, a comeback, a sending off — not to reproduce a real line-up, and inventing a
/// squad would put made-up facts about identifiable people into the project.
///
/// Clubs and competition are real because the case study is Clube Náutico Capibaribe in the
/// 2026 Série B, as stated in Chapter 4.
nonisolated enum SampleMatches {
    // MARK: - Teams

    static let nautico = Team(
        id: "nautico",
        name: "Clube Náutico Capibaribe",
        shortName: "Náutico",
        nickname: "Timbu",
        crestURL: nil
    )

    static let crb = Team(
        id: "crb",
        name: "Clube de Regatas Brasil",
        shortName: "CRB",
        nickname: nil,
        crestURL: nil
    )

    // MARK: - Matches

    /// A live match in the second half, after a comeback.
    ///
    /// Event sequence is deliberate: CRB opens the score, Náutico equalises, Náutico goes
    /// ahead. That covers the three hardest narration cases in one match, because each goal
    /// needs a different sentence for the same event kind.
    static let liveComeback = Match(
        id: "match-comeback",
        competition: .brasileiraoSerieB,
        season: 2026,
        homeTeam: nautico,
        awayTeam: crb,
        kickoff: Date(timeIntervalSince1970: 1_774_000_000),
        status: .secondHalf,
        elapsedMinutes: 67,
        score: Score(home: 2, away: 1),
        events: [
            MatchEvent(
                kind: .periodStart,
                minute: 0,
                stoppageMinute: nil,
                team: nautico,
                player: nil,
                relatedPlayer: nil,
                detail: "1st half"
            ),
            MatchEvent(
                kind: .goal,
                minute: 23,
                stoppageMinute: nil,
                team: crb,
                player: "Ribamar",
                relatedPlayer: "Léo Pereira",
                detail: "Normal Goal"
            ),
            MatchEvent(
                kind: .yellowCard,
                minute: 39,
                stoppageMinute: nil,
                team: nautico,
                player: "Wanderson",
                relatedPlayer: nil,
                detail: "Foul"
            ),
            MatchEvent(
                kind: .periodEnd,
                minute: 45,
                stoppageMinute: 2,
                team: nautico,
                player: nil,
                relatedPlayer: nil,
                detail: "1st half"
            ),
            MatchEvent(
                kind: .goal,
                minute: 52,
                stoppageMinute: nil,
                team: nautico,
                player: "Marquinhos",
                relatedPlayer: "Paulo Sérgio",
                detail: "Normal Goal"
            ),
            MatchEvent(
                kind: .substitution,
                minute: 61,
                stoppageMinute: nil,
                team: crb,
                player: "Anselmo",
                relatedPlayer: "Ribamar",
                detail: "Substitution 1"
            ),
            MatchEvent(
                kind: .penaltyScored,
                minute: 66,
                stoppageMinute: nil,
                team: nautico,
                player: "Jean Carlos",
                relatedPlayer: nil,
                detail: "Penalty"
            )
        ]
    )

    /// A match yet to start, for the pre-match state of the interface.
    static let scheduled = Match(
        id: "match-scheduled",
        competition: .brasileiraoSerieB,
        season: 2026,
        homeTeam: crb,
        awayTeam: nautico,
        kickoff: Date(timeIntervalSince1970: 1_774_600_000),
        status: .scheduled,
        elapsedMinutes: nil,
        score: .goalless,
        events: []
    )

    /// A finished match with a sending off, for replaying past events.
    static let finishedWithRedCard = Match(
        id: "match-finished",
        competition: .brasileiraoSerieB,
        season: 2026,
        homeTeam: nautico,
        awayTeam: crb,
        kickoff: Date(timeIntervalSince1970: 1_773_400_000),
        status: .finished,
        elapsedMinutes: 90,
        score: Score(home: 1, away: 1),
        events: [
            MatchEvent(
                kind: .goal,
                minute: 12,
                stoppageMinute: nil,
                team: nautico,
                player: "Marquinhos",
                relatedPlayer: nil,
                detail: "Normal Goal"
            ),
            MatchEvent(
                kind: .redCard,
                minute: 58,
                stoppageMinute: nil,
                team: nautico,
                player: "Wanderson",
                relatedPlayer: nil,
                detail: "Violent Conduct"
            ),
            MatchEvent(
                kind: .goal,
                minute: 88,
                stoppageMinute: nil,
                team: crb,
                player: "Anselmo",
                relatedPlayer: nil,
                detail: "Normal Goal"
            )
        ]
    )

    static let all: [Match] = [liveComeback, scheduled, finishedWithRedCard]
}

nonisolated extension InMemoryMatchDataProvider {
    /// Provider preloaded with the sample data, for previews and tests.
    static func sample(latency: Duration = .zero) -> InMemoryMatchDataProvider {
        InMemoryMatchDataProvider(matches: SampleMatches.all, latency: latency)
    }
}
