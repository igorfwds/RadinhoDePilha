import Foundation

/// Translates API-Football payloads into the domain.
///
/// The only place that knows both vocabularies. Everything the vendor does oddly is corrected
/// here, so that the rest of the app can trust the domain's own guarantees.
///
/// Three corrections are worth naming, because each was found in real responses rather than in
/// the documentation:
///
/// 1. **Substitution players are swapped.** The vendor puts the player going *off* in `player`
///    and the one coming *on* in `assist`; ``MatchEvent`` documents the opposite. Mapping field
///    to field would make the app announce substitutions backwards.
/// 2. **Events are not chronological.** Real payloads contain 45+3 before 45+1. ``Match``
///    promises chronological order, so the mapper sorts.
/// 3. **Period boundaries do not exist.** The vendor reports no kick-off or half-time event, so
///    they are derived from the fixture status.
nonisolated enum APIFootballMapper {
    // MARK: - Match

    static func match(from item: APIFootballFixtureItem) -> Match {
        let home = ClubDirectory.team(id: item.teams.home.id, vendorName: item.teams.home.name)
        let away = ClubDirectory.team(id: item.teams.away.id, vendorName: item.teams.away.name)
        let status = status(from: item.fixture.status.short)

        return Match(
            id: String(item.fixture.id),
            competition: competition(fromLeagueID: item.league.id),
            season: item.league.season,
            homeTeam: home,
            awayTeam: away,
            kickoff: item.fixture.date,
            status: status,
            elapsedMinutes: item.fixture.status.elapsed,
            // Null goals mean "not started", which is not the same as nil-coalescing to a draw
            // after kick-off; before kick-off zero is the honest reading either way.
            score: Score(home: item.goals.home ?? 0, away: item.goals.away ?? 0),
            events: []
        )
    }

    /// A match with its events attached, in the order they happened.
    static func match(
        from item: APIFootballFixtureItem,
        events: [APIFootballEvent]
    ) -> Match {
        let base = match(from: item)
        let reported = events.compactMap { event(from: $0, in: base) }
        let derived = periodEvents(for: base, reported: reported)

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
            events: chronological(reported + derived)
        )
    }

    // MARK: - Status

    static func status(from short: String) -> MatchStatus {
        switch short.uppercased() {
        case "TBD", "NS": .scheduled
        case "1H": .firstHalf
        case "HT": .halfTime
        case "2H": .secondHalf
        case "ET", "BT": .extraTime
        case "P": .penaltyShootout
        case "FT", "AET", "PEN": .finished
        case "PST": .postponed
        case "CANC", "ABD", "AWD", "WO": .cancelled
        // `LIVE` means "in progress, minute unknown", `SUSP` and `INT` mean temporarily halted.
        // None map cleanly, and guessing would put a wrong period name into the narration.
        default: .unknown
        }
    }

    // MARK: - Events

    static func event(from dto: APIFootballEvent, in match: Match) -> MatchEvent? {
        guard let team = match.team(withID: String(dto.team.id)) else { return nil }

        let kind = kind(type: dto.type, detail: dto.detail)
        guard kind != .unknown else { return nil }

        let isSubstitution = kind == .substitution

        return MatchEvent(
            kind: kind,
            minute: dto.time.elapsed,
            stoppageMinute: dto.time.extra,
            team: team,
            // Swapped for substitutions: the domain's `player` is whoever comes on, and the
            // vendor puts that in `assist`.
            player: isSubstitution ? dto.assist.name : dto.player.name,
            relatedPlayer: isSubstitution ? dto.player.name : dto.assist.name,
            detail: dto.detail
        )
    }

    static func kind(type: String, detail: String) -> MatchEventKind {
        // Case-insensitive because the vendor is inconsistent: the docs say `Subst`, the API
        // sends `subst`.
        let normalisedDetail = detail.lowercased()

        switch type.lowercased() {
        case "goal":
            switch normalisedDetail {
            case "own goal": return .ownGoal
            case "penalty": return .penaltyScored
            case "missed penalty": return .penaltyMissed
            default: return .goal
            }

        case "card":
            switch normalisedDetail {
            case "red card": return .redCard
            case "second yellow card": return .secondYellowCard
            case "yellow card": return .yellowCard
            default: return .unknown
            }

        case "subst":
            return .substitution

        case "var":
            // The documented details are `Goal cancelled` and `Penalty confirmed`, but real
            // responses also carry `Penalty awarded`. Treating any VAR entry as a review is
            // right: the engine narrates the review itself, not its outcome, and the outcome
            // arrives as its own event.
            return .varDecision

        default:
            return .unknown
        }
    }

    /// Kick-off and final-whistle events, which the vendor does not report.
    ///
    /// Derived from status rather than from the clock, so a match loaded mid-play still carries
    /// the boundaries already passed.
    ///
    /// The end of a period is placed after the stoppage time actually played, taken from the
    /// reported events. Anchoring it to minute 45 or 90 flat would put "fim do primeiro tempo"
    /// before a goal scored at 45+2 — which, for a listener following by ear, reads as the
    /// referee blowing the whistle and the match continuing anyway.
    static func periodEvents(for match: Match, reported: [MatchEvent] = []) -> [MatchEvent] {
        var events: [MatchEvent] = []

        /// Latest stoppage minute reported for a given regulation minute.
        func lastStoppage(atMinute minute: Int) -> Int? {
            reported
                .filter { $0.minute == minute }
                .compactMap(\.stoppageMinute)
                .max()
        }

        func boundary(_ kind: MatchEventKind, minute: Int, stoppage: Int?, detail: String) {
            events.append(
                MatchEvent(
                    kind: kind,
                    minute: minute,
                    stoppageMinute: stoppage,
                    // Attributed to the home side purely because the type requires a team; the
                    // narration for period boundaries never names one.
                    team: match.homeTeam,
                    player: nil,
                    relatedPlayer: nil,
                    detail: detail
                )
            )
        }

        let status = match.status
        let started: Set<MatchStatus> = [
            .firstHalf, .halfTime, .secondHalf, .extraTime, .penaltyShootout, .finished
        ]
        guard started.contains(status) else { return [] }

        boundary(.periodStart, minute: 0, stoppage: nil, detail: "1st half")

        let firstHalfOver: Set<MatchStatus> = [
            .halfTime, .secondHalf, .extraTime, .penaltyShootout, .finished
        ]
        if firstHalfOver.contains(status) {
            boundary(
                .periodEnd,
                minute: 45,
                stoppage: lastStoppage(atMinute: 45),
                detail: "1st half"
            )
        }

        let secondHalfStarted: Set<MatchStatus> = [
            .secondHalf, .extraTime, .penaltyShootout, .finished
        ]
        if secondHalfStarted.contains(status) {
            boundary(.periodStart, minute: 45, stoppage: nil, detail: "2nd half")
        }

        if status == .finished {
            boundary(
                .periodEnd,
                minute: 90,
                stoppage: lastStoppage(atMinute: 90),
                detail: "2nd half"
            )
        }

        return events
    }

    /// Orders events the way they happened.
    ///
    /// Necessary because the vendor does not: a real payload for Náutico 4×3 Tombense lists 45+3
    /// before 45+1. Period boundaries sort before other events in the same minute, so kick-off
    /// precedes a first-minute goal.
    static func chronological(_ events: [MatchEvent]) -> [MatchEvent] {
        events.sorted { lhs, rhs in
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }

            let lhsStoppage = lhs.stoppageMinute ?? 0
            let rhsStoppage = rhs.stoppageMinute ?? 0
            if lhsStoppage != rhsStoppage { return lhsStoppage < rhsStoppage }

            return sortRank(lhs.kind) < sortRank(rhs.kind)
        }
    }

    private static func sortRank(_ kind: MatchEventKind) -> Int {
        switch kind {
        case .periodStart: 0
        case .periodEnd: 2
        default: 1
        }
    }

    // MARK: - Competition

    /// Maps the vendor's league identifier onto the closed domain set.
    ///
    /// Returns Série B for anything unrecognised, which is safe while the app follows a single
    /// competition and is the seam to widen when it follows more.
    static func competition(fromLeagueID id: Int) -> Competition {
        switch id {
        case 71: .brasileiraoSerieA
        case 75: .brasileiraoSerieC
        case pernambucanoLeagueID: .pernambucano
        default: .brasileiraoSerieB
        }
    }

    /// API-Football's identifier for the competition this app follows.
    static let serieBLeagueID = 72

    /// State championship, present because recorded demonstration matches come from it.
    static let pernambucanoLeagueID = 622

    /// API-Football's identifier for Clube Náutico Capibaribe.
    static let nauticoTeamID = 755
}
