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

/// Vendor type identifiers, the same for team statistics and for player details.
nonisolated enum SportmonksPlayDerivation {
    static let corners = 34
    static let fouls = 56
    static let offsides = 51
    static let foulsDrawn = 96

    /// Most plays of one kind accepted from a single change.
    ///
    /// A jump larger than this is the vendor correcting its totals, not that many fouls in a few
    /// seconds, and narrating a burst of them would only be noise.
    static let burstLimit = 2

    /// The plays between two sets of totals, with nothing remembered from before.
    ///
    /// A convenience over ``SportmonksPlayLedger`` for the simple case, and for tests.
    static func events(
        from old: SportmonksCounters,
        to new: SportmonksCounters,
        in match: Match
    ) -> [MatchEvent] {
        var ledger = SportmonksPlayLedger()
        let now = Date()

        _ = ledger.advance(to: old, in: match, at: now)

        return ledger.advance(to: new, in: match, at: now)
    }
}

/// Turns successive sets of totals into individual plays.
///
/// The vendor reports goals, cards and substitutions one by one, but corners, fouls and offsides
/// only as totals that grow during the match. A total that went from 3 to 4 between two requests
/// a few seconds apart means one happened in between, and that is enough to narrate it.
///
/// ## Why names arrive separately
///
/// The same comparison on the player totals says who committed a foul and who suffered it. But
/// the two do not move together: measured over a whole match, the player totals changed in the
/// same thirty seconds as the team total for under half of the fouls, up to a minute later for
/// most of the rest, and occasionally before.
///
/// So a foul is announced as soon as the team total says so, and the names follow as a second
/// short sentence when they arrive. Waiting for the names would have delayed every foul by up to
/// a minute for the sake of the ones that get a name at all.
///
/// A value type with no clock of its own: the time is passed in, which keeps the whole thing
/// deterministic and lets a recorded match be replayed through it.
nonisolated struct SportmonksPlayLedger: Sendable {
    typealias Side = SportmonksCounters.Side

    /// Names for one play.
    nonisolated private struct Attribution: Sendable {
        let player: String?
        let relatedPlayer: String?
        let arrivedAt: Date
    }

    /// A play already narrated without names, waiting for them.
    nonisolated private struct UnnamedPlay: Sendable {
        let minute: Int
        let sequence: Int
        let narratedAt: Date
    }

    nonisolated private struct Key: Hashable, Sendable {
        let kind: MatchEventKind
        let side: Side
    }

    /// How long a play waits for its names before being left without them.
    static let namesExpectedWithin: TimeInterval = 120

    /// How long names that arrived early are kept for the play they belong to.
    static let earlyNamesKeptFor: TimeInterval = 75

    /// A gap between responses longer than this resets the baseline.
    ///
    /// After a stretch without signal the totals have moved by several plays, none of which can
    /// be placed in time any more. Narrating them on reconnection would report stale fouls as if
    /// they had just happened.
    static let baselineExpiresAfter: TimeInterval = 60

    private var counters: SportmonksCounters?
    private var updatedAt: Date?
    private var unnamed: [Key: [UnnamedPlay]] = [:]
    private var earlyNames: [Key: [Attribution]] = [:]

    init() {}

    /// Takes the latest totals and returns the plays they reveal.
    ///
    /// The first call only sets the baseline: its totals say how many corners there have been,
    /// not when, so nothing is narrated from it.
    mutating func advance(
        to new: SportmonksCounters,
        in match: Match,
        at now: Date
    ) -> [MatchEvent] {
        defer {
            counters = new
            updatedAt = now
        }

        guard let old = counters,
              let updatedAt,
              now.timeIntervalSince(updatedAt) <= Self.baselineExpiresAfter
        else {
            unnamed.removeAll()
            earlyNames.removeAll()
            return []
        }

        forgetExpired(at: now)

        var events: [MatchEvent] = []

        for side in [Side.home, .away] {
            let kinds: [(MatchEventKind, Int, [Attribution])] = [
                (.corner, SportmonksPlayDerivation.corners, []),
                (
                    .foul,
                    SportmonksPlayDerivation.fouls,
                    foulNames(on: side, from: old, to: new, at: now)
                ),
                (
                    .offside,
                    SportmonksPlayDerivation.offsides,
                    offsideNames(on: side, from: old, to: new, at: now)
                )
            ]

            for (kind, type, names) in kinds {
                events += plays(
                    kind,
                    type: type,
                    on: side,
                    names: names,
                    from: old,
                    to: new,
                    in: match,
                    at: now
                )
            }
        }

        return events
    }

    // MARK: - Plays

    /// The plays of one kind for one side, and the names for plays announced earlier.
    private mutating func plays(
        _ kind: MatchEventKind,
        type: Int,
        on side: Side,
        names arrived: [Attribution],
        from old: SportmonksCounters,
        to new: SportmonksCounters,
        in match: Match,
        at now: Date
    ) -> [MatchEvent] {
        let key = Key(kind: kind, side: side)
        let team = side == .home ? match.homeTeam : match.awayTeam
        var events: [MatchEvent] = []
        var names = arrived

        // Names go first to the plays that have been waiting longest: a name that arrives now
        // far more often belongs to a foul from half a minute ago than to one from this instant.
        while !names.isEmpty, var waiting = unnamed[key], !waiting.isEmpty {
            let play = waiting.removeFirst()
            let attribution = names.removeFirst()
            unnamed[key] = waiting

            events.append(
                MatchEvent(
                    kind: kind == .foul ? .foulAttribution : .offsideAttribution,
                    minute: play.minute,
                    stoppageMinute: nil,
                    team: team,
                    player: attribution.player,
                    relatedPlayer: attribution.relatedPlayer,
                    detail: "derived from totals",
                    sequence: play.sequence
                )
            )
        }

        // Whatever is left arrived before its play, and is kept for it.
        earlyNames[key, default: []] += names

        let before = old.teams[type]?[side] ?? 0

        // Missing from the new response reads as "unchanged", not as a drop to zero.
        let after = new.teams[type]?[side] ?? before
        let increase = after - before

        guard increase > 0 else { return events }

        for step in 1...min(increase, SportmonksPlayDerivation.burstLimit) {
            let sequence = before + step
            let minute = match.elapsedMinutes ?? 0
            var attribution: Attribution?

            if var early = earlyNames[key], !early.isEmpty {
                attribution = early.removeFirst()
                earlyNames[key] = early
            } else if kind != .corner {
                unnamed[key, default: []].append(
                    UnnamedPlay(minute: minute, sequence: sequence, narratedAt: now)
                )
            }

            events.append(
                MatchEvent(
                    kind: kind,
                    minute: minute,
                    stoppageMinute: nil,
                    team: team,
                    player: attribution?.player,
                    relatedPlayer: attribution?.relatedPlayer,
                    detail: "derived from totals",
                    sequence: sequence
                )
            )
        }

        return events
    }

    // MARK: - Names

    /// Who committed, and who suffered, the fouls whose player totals changed just now.
    ///
    /// The offender is on the fouling side, the victim on the other. They are paired only when
    /// one of each changed: with two fouls at once there is no telling which victim belongs to
    /// which offender, so each offender is reported alone rather than guessed at.
    private func foulNames(
        on side: Side,
        from old: SportmonksCounters,
        to new: SportmonksCounters,
        at now: Date
    ) -> [Attribution] {
        let offenders = risen(SportmonksPlayDerivation.fouls, on: side, from: old, to: new)
        let victims = risen(
            SportmonksPlayDerivation.foulsDrawn,
            on: side.opponent,
            from: old,
            to: new
        )

        if offenders.count == 1 {
            let victim = victims.count == 1 ? victims.first : nil

            return [Attribution(player: offenders.first, relatedPlayer: victim, arrivedAt: now)]
        }

        return offenders.map { Attribution(player: $0, relatedPlayer: nil, arrivedAt: now) }
    }

    private func offsideNames(
        on side: Side,
        from old: SportmonksCounters,
        to new: SportmonksCounters,
        at now: Date
    ) -> [Attribution] {
        risen(SportmonksPlayDerivation.offsides, on: side, from: old, to: new)
            .map { Attribution(player: $0, relatedPlayer: nil, arrivedAt: now) }
    }

    /// Names of the players on a side whose total of a given type increased, in a stable order.
    private func risen(
        _ type: Int,
        on side: Side,
        from old: SportmonksCounters,
        to new: SportmonksCounters
    ) -> [String] {
        (new.players[type] ?? [:])
            .filter { id, value in
                new.playerSides[id] == side && value > (old.players[type]?[id] ?? 0)
            }
            .keys
            .sorted()
            .compactMap { new.playerNames[$0] }
    }

    /// Drops plays that will not get a name any more, and names whose play never came.
    private mutating func forgetExpired(at now: Date) {
        for key in unnamed.keys {
            unnamed[key]?.removeAll {
                now.timeIntervalSince($0.narratedAt) > Self.namesExpectedWithin
            }
        }

        for key in earlyNames.keys {
            earlyNames[key]?.removeAll {
                now.timeIntervalSince($0.arrivedAt) > Self.earlyNamesKeptFor
            }
        }
    }
}

/// Remembers the totals of each match between requests, and the plays worked out so far.
///
/// An `actor` because the provider that owns it is a value shared across tasks, and this is the
/// one piece of state it needs: without the previous totals there is nothing to compare against.
actor SportmonksPlayTracker {
    private var ledgers: [String: SportmonksPlayLedger] = [:]
    private var derived: [String: [MatchEvent]] = [:]

    /// Whether the richer request is still worth making this session.
    private(set) var shouldRequestTotals = true

    func stopRequestingTotals() {
        shouldRequestTotals = false
    }

    /// Adds the plays worked out so far to a freshly mapped match.
    func enrich(_ match: Match, from fixture: SportmonksFixture, at now: Date = Date()) -> Match {
        if fixture.statistics != nil, match.isLive {
            var ledger = ledgers[match.id] ?? SportmonksPlayLedger()

            derived[match.id, default: []] += ledger.advance(
                to: SportmonksCounters(fixture: fixture),
                in: match,
                at: now
            )
            ledgers[match.id] = ledger
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
