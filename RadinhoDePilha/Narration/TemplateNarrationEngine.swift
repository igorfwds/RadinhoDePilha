import Foundation

/// Narration engine driven by contextualised templates.
///
/// Deterministic by design, and that is a defensible choice rather than a limitation. The same
/// input always yields the same sentence, which makes the output testable, reproducible in the
/// dissertation, free of inference latency and free of per-request cost. A language model would
/// offer richer vocabulary at the price of all four.
///
/// What makes the output more than string interpolation is context. The same event kind yields
/// different sentences depending on what the goal means for the match: opening the score,
/// equalising, completing a comeback. That derivation is the semantic translation the project is
/// about.
///
/// Wording lives in ``RadioPhrasebook``, kept apart so that the vocabulary can change, or be
/// swapped for a different narrator persona, without touching match logic.
nonisolated struct TemplateNarrationEngine: NarrationEngine {
    private let phrasebook: RadioPhrasebook

    init(phrasebook: RadioPhrasebook = RadioPhrasebook()) {
        self.phrasebook = phrasebook
    }

    /// Builds an engine narrating in the given persona.
    ///
    /// The persona reaches the wording and nothing else: match logic, priorities and goal-context
    /// classification are identical across personas. That is deliberate, and it is what lets the
    /// same events be narrated three ways and compared under one set of tests.
    init(persona: NarratorPersona) {
        self.init(phrasebook: RadioPhrasebook(persona: persona))
    }

    /// Persona this engine narrates in.
    var persona: NarratorPersona { phrasebook.persona }

    func narrate(_ event: MatchEvent, in match: Match) -> Narration? {
        guard let text = text(for: event, in: match) else { return nil }

        return Narration(
            id: event.id,
            text: text,
            priority: priority(for: event.kind),
            minute: event.minute,
            stoppageMinute: event.stoppageMinute
        )
    }

    /// Classifies what a goal means for the side that scored it.
    ///
    /// Exposed rather than private so tests can assert the classification without depending on
    /// the wording, which has several accepted forms.
    func goalContext(for event: MatchEvent, in match: Match) -> GoalContext {
        let before = score(upTo: event, in: match)
        let after = score(upToAndIncluding: event, in: match)

        let scorerIsHome = event.team.id == match.homeTeam.id
        let marginBefore = margin(of: before, forHome: scorerIsHome)
        let marginAfter = margin(of: after, forHome: scorerIsHome)

        if before == .goalless {
            return .opensScore
        }
        if marginAfter == 0 {
            return .equalises
        }
        if marginAfter < 0 {
            return .reducesDeficit
        }
        if marginBefore > 0 {
            return .extendsLead
        }
        // Went from level to ahead. Whether that is a comeback depends on the side having
        // trailed earlier in the match, which is the difference between "desempata o jogo" and
        // "é a virada".
        return trailedEarlier(event.team, before: event, in: match) ? .comeback : .takesLead
    }

    func summary(of match: Match) -> Narration {
        let key = summaryKey(for: match)
        let home = spokenName(of: match.homeTeam, key: key + "-home")
        let away = spokenName(of: match.awayTeam, key: key + "-away")

        let sentences = [
            pick(phrasebook.summaryOpening(), key: key + "-opening"),
            pick(
                phrasebook.scoreline(
                    homeTeam: home,
                    homeGoals: match.score.home,
                    awayTeam: away,
                    awayGoals: match.score.away
                ),
                key: key + "-score"
            ),
            stageSentence(for: match, key: key)
        ] + scorerSentences(for: match, key: key, homeName: home, awayName: away)

        return Narration(
            id: key,
            text: sentences.filter { !$0.isEmpty }.joined(separator: " "),
            // Above ordinary events but below goals. The listener asked for this and should not
            // wait behind a substitution, yet a goal happening right now still matters more than
            // a recap of what already happened.
            priority: .high,
            minute: match.elapsedMinutes ?? 0,
            stoppageMinute: nil
        )
    }
}

// MARK: - Deterministic variety

nonisolated private extension TemplateNarrationEngine {
    /// Picks one alternative, always the same one for the same event.
    ///
    /// Determinism is not a detail here. Replaying a moment must sound exactly as it did live,
    /// and the tests must be able to assert on output at all.
    func pick(_ options: [String], for event: MatchEvent, salt: String = "") -> String {
        pick(options, key: event.id + salt)
    }

    /// Picks one alternative from an arbitrary key.
    ///
    /// Needed by the summary, which describes a state rather than an event and so has no event
    /// identifier to key on.
    func pick(_ options: [String], key: String) -> String {
        guard !options.isEmpty else { return "" }
        let index = Int(stableHash(key) % UInt64(options.count))
        return options[index]
    }

    /// FNV-1a hash, stable across processes.
    ///
    /// Swift's own `hashValue` is seeded per process, so the same string hashes differently
    /// between launches. Using it here would mean an event narrated one way during the match is
    /// narrated another way on replay, and tests that pass in one run and fail in the next.
    func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    /// How to refer to a side in this narration: club name or supporters' nickname.
    ///
    /// Radio commentary alternates between the two, and reproducing that alternation is part of
    /// sounding like radio. The salt is keyed on the team rather than on the sentence position, so
    /// that every mention of the same side within one narration uses the same form — "Gol do
    /// Timbu" followed by "o Náutico fica com dez" would make a listener wonder whether two
    /// different clubs were involved.
    func spokenName(of team: Team, for event: MatchEvent) -> String {
        pick(team.spokenNames, for: event, salt: "team-\(team.id)")
    }

    /// How to refer to a side outside the context of an event.
    func spokenName(of team: Team, key: String) -> String {
        pick(team.spokenNames, key: key + "-team-\(team.id)")
    }
}

// MARK: - Summary construction

nonisolated private extension TemplateNarrationEngine {
    /// Identity of a summary, and the seed for its wording.
    ///
    /// Built from the match state rather than from the clock, so that summarising the same
    /// situation twice produces the same passage — testable, and reassuring to a listener who
    /// asks again a few seconds later — while a changed score or minute yields fresh wording.
    func summaryKey(for match: Match) -> String {
        "summary-\(match.id)-\(match.score.home)-\(match.score.away)-\(match.elapsedMinutes ?? -1)-\(match.status.rawValue)"
    }

    func stageSentence(for match: Match, key: String) -> String {
        switch match.status {
        case .scheduled:
            pick(phrasebook.summaryNotStarted(), key: key + "-stage")
        case .halfTime:
            pick(phrasebook.summaryHalfTime(), key: key + "-stage")
        case .finished:
            pick(phrasebook.summaryFinished(), key: key + "-stage")
        case .firstHalf, .secondHalf, .extraTime, .penaltyShootout:
            elapsedStageSentence(for: match, key: key)
        case .postponed, .cancelled, .unknown:
            // Handled as an exception state by the caller, which can say more about it than a
            // recap of a match that is not being played.
            ""
        }
    }

    func elapsedStageSentence(for match: Match, key: String) -> String {
        guard let minute = match.elapsedMinutes else { return "" }

        return pick(
            phrasebook.summaryStage(period: .containing(minute: minute), minute: minute),
            key: key + "-stage"
        )
    }

    /// One sentence per side that has scored, or a single sentence when nobody has.
    func scorerSentences(
        for match: Match,
        key: String,
        homeName: String,
        awayName: String
    ) -> [String] {
        let home = scorers(for: match.homeTeam, in: match)
        let away = scorers(for: match.awayTeam, in: match)

        guard !home.isEmpty || !away.isEmpty else {
            return [pick(phrasebook.summaryGoalless(), key: key + "-goalless")]
        }

        return [
            (homeName, home, "home"),
            (awayName, away, "away")
        ].compactMap { name, list, salt in
            guard !list.isEmpty else { return nil }

            return pick(
                phrasebook.summaryScorers(team: name, scorers: listed(list)),
                key: key + "-scorers-" + salt
            )
        }
    }

    /// Scorers credited to one side, with the minute of each goal.
    ///
    /// Own goals count for the side that benefits, not for the side of the player who put the
    /// ball in, and are marked as such: crediting "Ribamar" with a goal for the opposition
    /// without qualification would state something that did not happen.
    func scorers(for team: Team, in match: Match) -> [String] {
        match.events.compactMap { event in
            guard let player = event.player else { return nil }

            switch event.kind {
            case .goal, .penaltyScored:
                guard event.team.id == team.id else { return nil }
                return "\(player) aos \(event.minute)"
            case .ownGoal:
                guard event.team.id != team.id else { return nil }
                return "\(player), contra, aos \(event.minute)"
            default:
                return nil
            }
        }
    }

    /// Joins names the way they are spoken: "A, B e C".
    func listed(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }

        return items.dropLast().joined(separator: ", ") + " e " + last
    }
}

// MARK: - Sentence construction

nonisolated private extension TemplateNarrationEngine {
    func text(for event: MatchEvent, in match: Match) -> String? {
        switch event.kind {
        case .goal, .penaltyScored:
            goalSentence(for: event, in: match)
        case .ownGoal:
            ownGoalSentence(for: event, in: match)
        case .penaltyMissed:
            penaltyMissedSentence(for: event)
        case .yellowCard:
            yellowCardSentence(for: event)
        case .secondYellowCard, .redCard:
            sendingOffSentence(for: event, in: match)
        case .substitution:
            substitutionSentence(for: event)
        case .varDecision:
            varSentence(for: event)
        case .periodStart:
            periodStartSentence(for: event)
        case .periodEnd:
            periodEndSentence(for: event, in: match)
        case .unknown:
            // Silence on purpose. Narration is a serial channel, and speaking an event the app
            // cannot describe would spend it on noise.
            nil
        }
    }

    func goalSentence(for event: MatchEvent, in match: Match) -> String {
        let scorer = event.player ?? "O time"
        let after = score(upToAndIncluding: event, in: match)

        var parts = [
            timeMarker(for: event),
            pick(
                phrasebook.goalAnnouncement(
                    team: spokenName(of: event.team, for: event),
                    isPenalty: event.kind == .penaltyScored
                ),
                for: event
            ),
            pick(
                phrasebook.meaning(goalContext(for: event, in: match), scorer: scorer),
                for: event,
                salt: "meaning"
            )
        ]

        if let assist = event.relatedPlayer, event.kind != .penaltyScored {
            parts.append(pick(phrasebook.assist(player: assist), for: event, salt: "assist"))
        }

        parts.append(scoreline(after, in: match, for: event))

        return parts.joined(separator: " ")
    }

    func ownGoalSentence(for event: MatchEvent, in match: Match) -> String {
        let beneficiary = opponent(of: event.team, in: match)?.shortName ?? "o adversário"
        let after = score(upToAndIncluding: event, in: match)

        return [
            timeMarker(for: event),
            pick(
                phrasebook.ownGoal(
                    player: event.player ?? "Um jogador",
                    team: spokenName(of: event.team, for: event),
                    beneficiary: beneficiary
                ),
                for: event
            ),
            scoreline(after, in: match, for: event)
        ].joined(separator: " ")
    }

    func penaltyMissedSentence(for event: MatchEvent) -> String {
        [
            timeMarker(for: event),
            pick(
                phrasebook.penaltyMissed(
                    player: event.player ?? "O batedor",
                    team: spokenName(of: event.team, for: event)
                ),
                for: event
            )
        ].joined(separator: " ")
    }

    func yellowCardSentence(for event: MatchEvent) -> String {
        [
            timeMarker(for: event),
            pick(
                phrasebook.yellowCard(
                    player: event.player ?? "Um jogador",
                    team: spokenName(of: event.team, for: event)
                ),
                for: event
            )
        ].joined(separator: " ")
    }

    func sendingOffSentence(for event: MatchEvent, in match: Match) -> String {
        let remaining = playersRemaining(for: event.team, upToAndIncluding: event, in: match)

        return [
            timeMarker(for: event),
            pick(
                phrasebook.sendingOff(
                    player: event.player ?? "Um jogador",
                    team: spokenName(of: event.team, for: event),
                    isSecondYellow: event.kind == .secondYellowCard,
                    remainingSpelled: spelled(remaining)
                ),
                for: event
            )
        ].joined(separator: " ")
    }

    func substitutionSentence(for event: MatchEvent) -> String {
        [
            timeMarker(for: event),
            pick(
                phrasebook.substitution(
                    team: spokenName(of: event.team, for: event),
                    incoming: event.player,
                    outgoing: event.relatedPlayer
                ),
                for: event
            )
        ].joined(separator: " ")
    }

    func varSentence(for event: MatchEvent) -> String {
        [
            timeMarker(for: event),
            pick(phrasebook.varReview(), for: event)
        ].joined(separator: " ")
    }

    func periodStartSentence(for event: MatchEvent) -> String {
        // No time marker: "Aos 0 minutos do primeiro tempo. Começa o jogo." states the obvious.
        pick(phrasebook.periodStart(MatchPeriod.containing(minute: event.minute)), for: event)
    }

    func periodEndSentence(for event: MatchEvent, in match: Match) -> String {
        // A period ends on the minute that opens the next one, so the period being closed is the
        // one containing the minute just before.
        let period = MatchPeriod.containing(minute: max(0, event.minute - 1))
        let running = score(upToAndIncluding: event, in: match)

        return [
            pick(phrasebook.periodEnd(period), for: event),
            scoreline(running, in: match, for: event)
        ].joined(separator: " ")
    }

    func timeMarker(for event: MatchEvent) -> String {
        pick(
            phrasebook.timeMarker(
                minute: event.minute,
                stoppage: event.stoppageMinute,
                period: MatchPeriod.containing(minute: event.minute)
            ),
            for: event,
            salt: "time"
        )
    }

    func scoreline(_ score: Score, in match: Match, for event: MatchEvent) -> String {
        pick(
            phrasebook.scoreline(
                homeTeam: match.homeTeam.shortName,
                homeGoals: score.home,
                awayTeam: match.awayTeam.shortName,
                awayGoals: score.away
            ),
            for: event,
            salt: "score"
        )
    }
}

// MARK: - Context derivation

nonisolated private extension TemplateNarrationEngine {
    func margin(of score: Score, forHome isHome: Bool) -> Int {
        isHome ? score.home - score.away : score.away - score.home
    }

    /// Whether the side was behind at any point before the given event.
    func trailedEarlier(_ team: Team, before event: MatchEvent, in match: Match) -> Bool {
        let isHome = team.id == match.homeTeam.id
        var running = Score.goalless

        for earlier in events(upTo: event, in: match) {
            running = applying(earlier, to: running, in: match)
            if margin(of: running, forHome: isHome) < 0 { return true }
        }

        return false
    }

    /// Players still on the pitch for a side, after accounting for sendings off.
    ///
    /// Starts from eleven. Substitutions do not change the count, so only red cards and second
    /// bookings are tallied.
    func playersRemaining(
        for team: Team,
        upToAndIncluding event: MatchEvent,
        in match: Match
    ) -> Int {
        let dismissals = (events(upTo: event, in: match) + [event])
            .filter { $0.team.id == team.id }
            .filter { $0.kind == .redCard || $0.kind == .secondYellowCard }
            .count

        return max(0, 11 - dismissals)
    }
}

// MARK: - Score tallying

nonisolated private extension TemplateNarrationEngine {
    /// Score as it stood immediately before the given event.
    ///
    /// Recomputed from the event list rather than read from ``Match/score``, which reflects the
    /// present moment and would be wrong when narrating a past event during replay.
    func score(upTo event: MatchEvent, in match: Match) -> Score {
        events(upTo: event, in: match).reduce(Score.goalless) { running, earlier in
            applying(earlier, to: running, in: match)
        }
    }

    /// Score as it stood immediately after the given event.
    func score(upToAndIncluding event: MatchEvent, in match: Match) -> Score {
        applying(event, to: score(upTo: event, in: match), in: match)
    }

    /// Events that took place before the given one.
    ///
    /// Prefers position in the provider's list, which preserves ordering between events sharing a
    /// minute, and falls back to comparing minutes when the event is not part of the list — the
    /// case when narrating an event held elsewhere, such as a bookmark.
    func events(upTo event: MatchEvent, in match: Match) -> [MatchEvent] {
        if let index = match.events.firstIndex(where: { $0.id == event.id }) {
            return Array(match.events[..<index])
        }

        return match.events.filter { $0.absoluteMinute < event.absoluteMinute }
    }

    func applying(_ event: MatchEvent, to score: Score, in match: Match) -> Score {
        let scorerIsHome = event.team.id == match.homeTeam.id

        switch event.kind {
        case .goal, .penaltyScored:
            return scorerIsHome
                ? Score(home: score.home + 1, away: score.away)
                : Score(home: score.home, away: score.away + 1)
        case .ownGoal:
            // An own goal credits the opposing side.
            return scorerIsHome
                ? Score(home: score.home, away: score.away + 1)
                : Score(home: score.home + 1, away: score.away)
        default:
            return score
        }
    }

    func opponent(of team: Team, in match: Match) -> Team? {
        team.id == match.homeTeam.id ? match.awayTeam : match.homeTeam
    }
}

// MARK: - Formatting

nonisolated private extension TemplateNarrationEngine {
    /// Small numbers written out, so the synthesiser says "dez" instead of reading a digit.
    func spelled(_ number: Int) -> String {
        let words = [
            "zero", "um", "dois", "três", "quatro", "cinco",
            "seis", "sete", "oito", "nove", "dez", "onze"
        ]
        return words.indices.contains(number) ? words[number] : String(number)
    }

    func priority(for kind: MatchEventKind) -> NarrationPriority {
        switch kind {
        case .goal, .ownGoal, .penaltyScored:
            .critical
        case .penaltyMissed, .redCard, .secondYellowCard, .varDecision:
            .high
        case .yellowCard, .substitution, .periodStart, .periodEnd:
            .normal
        case .unknown:
            .low
        }
    }
}
