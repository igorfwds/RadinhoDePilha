import Foundation

/// The running totals of one response, reduced to what the derivation reads.
nonisolated struct SportmonksCounters: Equatable, Sendable {
    /// Which side a total belongs to.
    nonisolated enum Side: Hashable, Sendable {
        case home
        case away

        var opponent: Side { self == .home ? .away : .home }
    }

    /// Team totals: statistic type, then side.
    var teams: [Int: [Side: Int]] = [:]

    /// Player totals: detail type, then player identifier.
    var players: [Int: [Int: Int]] = [:]

    var playerNames: [Int: String] = [:]
    var playerSides: [Int: Side] = [:]

    init() {}

    init(fixture: SportmonksFixture) {
        // Sides come from the participants' own `location`, never from identifiers: the domain
        // may rename or renumber a club, and the totals must still land on the right side.
        var sides: [Int: Side] = [:]
        for participant in fixture.participants ?? [] {
            switch participant.meta?.location {
            case "home": sides[participant.id] = .home
            case "away": sides[participant.id] = .away
            default: break
            }
        }

        for statistic in fixture.statistics ?? [] {
            guard let type = statistic.typeId,
                  let participant = statistic.participantId,
                  let side = sides[participant],
                  let value = statistic.data?.value
            else { continue }

            teams[type, default: [:]][side] = value
        }

        for player in fixture.lineups ?? [] {
            guard let id = player.playerId,
                  let team = player.teamId,
                  let side = sides[team]
            else { continue }

            playerSides[id] = side
            playerNames[id] = player.playerName

            for detail in player.details ?? [] {
                guard let type = detail.typeId, let value = detail.data?.value else { continue }

                players[type, default: [:]][id] = value
            }
        }
    }
}

/// Works out individual plays from the difference between two sets of totals.
///
/// The vendor reports goals, cards and substitutions one by one, but corners, fouls and offsides
/// only as totals that grow during the match. A total that went from 3 to 4 between two requests
/// a few seconds apart means one happened in between, and that is enough to narrate it.
///
/// The same reasoning names the players. The team's fouls went up by one; if exactly one of its
/// players had their own fouls committed go up, that is who committed it, and if exactly one
/// opponent had their fouls suffered go up, that is who suffered it. When the player totals have
/// not caught up yet, or more than one changed, the play is narrated without a name instead of
/// with a guess.
nonisolated enum SportmonksPlayDerivation {
    // Vendor type identifiers, the same for team statistics and for player details.
    static let corners = 34
    static let fouls = 56
    static let offsides = 51
    static let foulsDrawn = 96

    /// Most plays of one kind accepted from a single change.
    ///
    /// A jump larger than this is the vendor correcting its totals, not that many fouls in a few
    /// seconds, and narrating a burst of them would only be noise.
    static let burstLimit = 2

    static func events(
        from old: SportmonksCounters,
        to new: SportmonksCounters,
        in match: Match
    ) -> [MatchEvent] {
        let kinds: [(type: Int, kind: MatchEventKind)] = [
            (corners, .corner),
            (fouls, .foul),
            (offsides, .offside)
        ]

        var events: [MatchEvent] = []

        for (type, kind) in kinds {
            for side in [SportmonksCounters.Side.home, .away] {
                let before = old.teams[type]?[side] ?? 0

                // Missing from the new response reads as "unchanged", not as a drop to zero.
                let after = new.teams[type]?[side] ?? before
                let increase = after - before

                guard increase > 0 else { continue }

                // Names only when the change is a single play: with two at once there is no
                // telling which player belongs to which.
                let isSinglePlay = increase == 1
                var player: String?
                var relatedPlayer: String?

                if isSinglePlay, kind == .foul {
                    player = solePlayer(on: side, whose: fouls, roseFrom: old, to: new)
                    relatedPlayer = solePlayer(
                        on: side.opponent,
                        whose: foulsDrawn,
                        roseFrom: old,
                        to: new
                    )
                } else if isSinglePlay, kind == .offside {
                    player = solePlayer(on: side, whose: offsides, roseFrom: old, to: new)
                }

                for step in 1...min(increase, burstLimit) {
                    events.append(
                        MatchEvent(
                            kind: kind,
                            minute: match.elapsedMinutes ?? 0,
                            stoppageMinute: nil,
                            team: side == .home ? match.homeTeam : match.awayTeam,
                            player: player,
                            relatedPlayer: relatedPlayer,
                            detail: "derived from totals",
                            sequence: before + step
                        )
                    )
                }
            }
        }

        return events
    }

    /// The one player on a side whose total of a given type increased, if there is exactly one.
    private static func solePlayer(
        on side: SportmonksCounters.Side,
        whose type: Int,
        roseFrom old: SportmonksCounters,
        to new: SportmonksCounters
    ) -> String? {
        let risen = (new.players[type] ?? [:]).filter { id, value in
            new.playerSides[id] == side && value > (old.players[type]?[id] ?? 0)
        }

        guard risen.count == 1, let id = risen.keys.first else { return nil }

        return new.playerNames[id]
    }
}

/// Remembers the totals of each match between requests, and the plays worked out so far.
///
/// An `actor` because the provider that owns it is a value shared across tasks, and this is the
/// one piece of state it needs: without the previous totals there is nothing to compare against.
actor SportmonksPlayTracker {
    private var counters: [String: SportmonksCounters] = [:]
    private var derived: [String: [MatchEvent]] = [:]

    /// Whether the richer request is still worth making this session.
    private(set) var shouldRequestTotals = true

    func stopRequestingTotals() {
        shouldRequestTotals = false
    }

    /// Adds the plays worked out so far to a freshly mapped match.
    ///
    /// The first response of a match only sets the baseline: its totals say how many corners
    /// there have been, not when, so nothing is narrated from it.
    func enrich(_ match: Match, from fixture: SportmonksFixture) -> Match {
        if fixture.statistics != nil {
            let current = SportmonksCounters(fixture: fixture)

            if match.isLive, let previous = counters[match.id] {
                derived[match.id, default: []] += SportmonksPlayDerivation.events(
                    from: previous,
                    to: current,
                    in: match
                )
            }

            counters[match.id] = current
        }

        guard let extra = derived[match.id], !extra.isEmpty else { return match }

        return Match(
            id: match.id,
            competition: match.competition,
            season: match.season,
            homeTeam: match.homeTeam,
            awayTeam: match.awayTeam,
            kickoff: match.kickoff,
            status: match.status,
            elapsedMinutes: match.elapsedMinutes,
            score: match.score,
            events: Self.chronological(match.events + extra)
        )
    }

    /// Orders by match minute, keeping the given order among events of the same minute.
    private static func chronological(_ events: [MatchEvent]) -> [MatchEvent] {
        events.enumerated()
            .sorted { lhs, rhs in
                let left = (lhs.element.minute, lhs.element.stoppageMinute ?? 0, lhs.offset)
                let right = (rhs.element.minute, rhs.element.stoppageMinute ?? 0, rhs.offset)

                return left < right
            }
            .map(\.element)
    }
}
