import Foundation

/// Translates Sportmonks payloads into the domain.
///
/// The counterpart of ``APIFootballMapper`` for the second vendor, and like it the only place that
/// knows both vocabularies.
///
/// Sportmonks needs fewer corrections than API-Football: substitutions already name the player
/// coming on first, and every event carries a sort order. Two things still have to be worked out
/// here, both checked against real responses:
///
/// 1. **The running minute overshoots the half.** A period's clock keeps counting through
///    stoppage, 46, 47…, where the domain's elapsed minute stays at 45 until the second half
///    starts. Passing it through would make the first half look finished while it is still being
///    played.
/// 2. **Period boundaries do not exist as events.** As with API-Football, kick-off and the final
///    whistle are derived from the fixture state.
nonisolated enum SportmonksMapper {
    // MARK: - Match

    /// A match with its events attached, in the order they happened.
    static func match(from fixture: SportmonksFixture) -> Match {
        let participants = fixture.participants ?? []
        // Falling back on array order keeps a fixture narratable if the vendor ever omits the
        // location; real responses carry it and list the away side first.
        let homeDTO = participants.first { $0.meta?.location == "home" } ?? participants.first
        let awayDTO = participants.first { $0.meta?.location == "away" } ?? participants.last

        let status = status(fromStateID: fixture.stateId)
        let kickoff = Date(timeIntervalSince1970: TimeInterval(fixture.startingAtTimestamp))

        let base = Match(
            id: String(fixture.id),
            competition: competition(fromLeagueID: fixture.leagueId),
            season: season(of: kickoff),
            homeTeam: team(from: homeDTO),
            awayTeam: team(from: awayDTO),
            kickoff: kickoff,
            status: status,
            elapsedMinutes: elapsedMinutes(from: fixture.periods ?? []),
            score: score(from: fixture.scores ?? []),
            events: []
        )

        let reported = (fixture.events ?? [])
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            .compactMap { event(from: $0, in: base) }

        // Deriving the boundaries and ordering the result is the same problem for both vendors,
        // so the logic already written and tested for API-Football is reused rather than copied.
        let derived = APIFootballMapper.periodEvents(for: base, reported: reported)

        return Match(
            id: base.id,
            competition: base.competition,
            season: base.season,
            homeTeam: base.homeTeam,
            awayTeam: base.awayTeam,
            kickoff: base.kickoff,
            status: base.status,
            elapsedMinutes: base.elapsedMinutes,
            score: base.score,
            events: APIFootballMapper.chronological(reported + derived)
        )
    }

    private static func team(from participant: SportmonksParticipant?) -> Team {
        guard let participant else {
            // A fixture with no participants cannot be narrated, but it must not crash either:
            // placeholders from the vendor's own schedule can arrive like this.
            return Team(id: "0", name: "A definir", shortName: "A definir", nickname: nil, crestURL: nil)
        }

        return ClubDirectory.team(id: participant.id, vendorName: participant.name)
    }

    /// Season year, taken from the kick-off.
    ///
    /// The vendor identifies seasons by an opaque number and names them `2026/2027` for European
    /// leagues. The Brazilian season runs inside one calendar year, so the year of the match is
    /// the season, and it costs no extra include.
    private static func season(of kickoff: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Recife") ?? .gmt

        return calendar.component(.year, from: kickoff)
    }

    // MARK: - Score and clock

    /// The running score, which the vendor lists among the per-half tallies as `CURRENT`.
    static func score(from scores: [SportmonksScore]) -> Score {
        func goals(_ side: String) -> Int {
            scores.first { $0.description == "CURRENT" && $0.score.participant == side }?.score.goals ?? 0
        }

        return Score(home: goals("home"), away: goals("away"))
    }

    /// Minutes elapsed, held at the end of the half during stoppage.
    ///
    /// Capped because the domain keeps stoppage apart from the regulation minute, and because the
    /// period boundaries are derived from this number: an uncapped 47 in first-half stoppage
    /// would read as "past the interval" and announce a second half that has not started.
    static func elapsedMinutes(from periods: [SportmonksPeriod]) -> Int? {
        let current = periods.first { $0.ticking == true }
            ?? periods.max { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }

        guard let current else { return nil }

        let end = (current.countsFrom ?? 0) + (current.periodLength ?? 45)

        guard current.ticking == true, let minutes = current.minutes else { return end }

        return min(minutes, end)
    }

    // MARK: - Status

    /// Maps the vendor's numeric state onto the domain.
    ///
    /// Covers the full table returned by the `states` endpoint. The names in the comments are the
    /// vendor's own `developer_name` for each number.
    static func status(fromStateID id: Int) -> MatchStatus {
        switch id {
        // NS, TBA, DELAYED: not started, whatever the reason.
        case 1, 13, 16: .scheduled
        case 2: .firstHalf  // INPLAY_1ST_HALF
        case 3: .halfTime  // HT
        case 22: .secondHalf  // INPLAY_2ND_HALF
        case 6, 23: .extraTime  // INPLAY_ET, INPLAY_ET_SECOND_HALF
        // BREAK (waiting for extra time), EXTRA_TIME_BREAK, PEN_BREAK.
        case 4, 21, 25: .breakTime
        case 9: .penaltyShootout  // INPLAY_PENALTIES
        // AWAITING_UPDATES: the feed stalled on a match that is being played. Kept live so the
        // polling loop does not stop at the exact moment it should be waiting for data to return.
        case 19: .inProgress
        case 18: .interrupted  // INTERRUPTED
        case 11: .suspended  // SUSPENDED
        case 5, 7, 8: .finished  // FT, AET, FT_PEN
        case 15: .abandoned  // ABANDONED
        case 14, 17: .awarded  // WO, AWARDED
        case 10: .postponed  // POSTPONED
        case 12, 20: .cancelled  // CANCELLED, DELETED
        default: .unknown
        }
    }

    // MARK: - Events

    static func event(from dto: SportmonksEvent, in match: Match) -> MatchEvent? {
        // A withdrawn card did not happen as far as the listener is concerned.
        guard dto.rescinded != true else { return nil }

        guard let participantID = dto.participantId,
              let team = match.team(withID: String(participantID)),
              let minute = dto.minute
        else { return nil }

        let kind = kind(fromTypeID: dto.typeId)
        guard kind != .unknown else { return nil }

        return MatchEvent(
            kind: kind,
            minute: minute,
            stoppageMinute: dto.extraMinute,
            team: team,
            player: dto.playerName,
            relatedPlayer: dto.relatedPlayerName,
            detail: dto.info ?? dto.addition
        )
    }

    /// Maps the vendor's numeric event type onto the domain.
    ///
    /// Shoot-out kicks (22 and 23) are left out on purpose: the domain has no kind for them, and
    /// Série B is a league, where they cannot occur.
    static func kind(fromTypeID id: Int) -> MatchEventKind {
        switch id {
        case 14: .goal  // GOAL
        case 15: .ownGoal  // OWNGOAL
        case 16: .penaltyScored  // PENALTY
        case 17: .penaltyMissed  // MISSED_PENALTY
        case 18: .substitution  // SUBSTITUTION
        case 19: .yellowCard  // YELLOWCARD
        case 20: .redCard  // REDCARD
        case 21: .secondYellowCard  // YELLOWREDCARD
        case 10: .varDecision  // VAR
        default: .unknown
        }
    }

    // MARK: - Competition

    /// Maps the vendor's league identifier onto the closed domain set.
    ///
    /// Returns Série B for anything unrecognised, the same choice ``APIFootballMapper`` makes
    /// while the app follows a single competition.
    static func competition(fromLeagueID id: Int) -> Competition {
        switch id {
        case 648: .brasileiraoSerieA
        case 657: .brasileiraoSerieC
        case 1316: .pernambucano
        default: .brasileiraoSerieB
        }
    }

    /// Sportmonks' identifier for the competition this app follows.
    static let serieBLeagueID = 651

    // MARK: - Followed club

    /// Whether a team is Náutico.
    ///
    /// By name rather than by identifier, unlike the API-Football side. The vendor's number for
    /// the club can only be read with a subscription that reaches Série B, and matching on the
    /// folded name works from the first request of that subscription with nothing to look up.
    static func isNautico(_ team: Team) -> Bool {
        ClubDirectory.normalised(team.name).contains("nautico")
            || ClubDirectory.normalised(team.shortName).contains("nautico")
    }
}
