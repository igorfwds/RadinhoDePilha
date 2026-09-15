import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Template narration engine")
struct TemplateNarrationEngineTests {
    let engine = TemplateNarrationEngine()

    // MARK: - Helpers

    private func match(
        events: [MatchEvent],
        status: MatchStatus = .secondHalf,
        score: Score = .goalless
    ) -> Match {
        Match(
            id: "test",
            competition: .brasileiraoSerieB,
            season: 2026,
            homeTeam: SampleMatches.nautico,
            awayTeam: SampleMatches.crb,
            kickoff: Date(timeIntervalSince1970: 0),
            status: status,
            elapsedMinutes: 60,
            score: score,
            events: events
        )
    }

    private func goal(
        _ team: Team,
        minute: Int,
        player: String? = "Jogador",
        assist: String? = nil,
        kind: MatchEventKind = .goal
    ) -> MatchEvent {
        MatchEvent(
            kind: kind,
            minute: minute,
            stoppageMinute: nil,
            team: team,
            player: player,
            relatedPlayer: assist,
            detail: nil
        )
    }

    private func event(
        _ kind: MatchEventKind,
        minute: Int,
        team: Team = SampleMatches.nautico,
        player: String? = nil,
        related: String? = nil
    ) -> MatchEvent {
        MatchEvent(
            kind: kind,
            minute: minute,
            stoppageMinute: nil,
            team: team,
            player: player,
            relatedPlayer: related,
            detail: nil
        )
    }

    // MARK: - Goal classification
    //
    // Asserts the derived meaning rather than the wording. Wording has several accepted
    // alternatives and will keep changing; the classification is the logic and must not.

    @Test("The first goal of a match opens the score")
    func firstGoalOpensScore() {
        let scored = goal(SampleMatches.nautico, minute: 10)

        #expect(engine.goalContext(for: scored, in: match(events: [scored])) == .opensScore)
    }

    @Test("A goal that levels the match is an equaliser")
    func levellingGoalEqualises() {
        let opener = goal(SampleMatches.crb, minute: 10)
        let leveller = goal(SampleMatches.nautico, minute: 20)

        #expect(
            engine.goalContext(for: leveller, in: match(events: [opener, leveller])) == .equalises
        )
    }

    @Test("Going ahead after having trailed is a comeback")
    func goingAheadAfterTrailingIsComeback() {
        let opener = goal(SampleMatches.crb, minute: 10)
        let leveller = goal(SampleMatches.nautico, minute: 20)
        let winner = goal(SampleMatches.nautico, minute: 30)
        let context = match(events: [opener, leveller, winner])

        #expect(engine.goalContext(for: winner, in: context) == .comeback)
    }

    @Test("Going ahead without having trailed is not a comeback")
    func goingAheadFromLevelIsNotComeback() {
        // Both sides have scored once, but the side scoring now was never behind: it opened the
        // score and was pegged back. This is the case a naive implementation gets wrong, calling
        // every level-to-lead goal a comeback.
        let ownOpener = goal(SampleMatches.nautico, minute: 5)
        let reply = goal(SampleMatches.crb, minute: 15)
        let winner = goal(SampleMatches.nautico, minute: 25)
        let context = match(events: [ownOpener, reply, winner])

        #expect(engine.goalContext(for: winner, in: context) == .takesLead)
    }

    @Test("A goal widening an existing lead extends it")
    func goalWideningLeadExtends() {
        let first = goal(SampleMatches.nautico, minute: 10)
        let second = goal(SampleMatches.nautico, minute: 20)

        #expect(
            engine.goalContext(for: second, in: match(events: [first, second])) == .extendsLead
        )
    }

    @Test("A goal scored while still behind reduces the deficit")
    func goalWhileBehindReducesDeficit() {
        let first = goal(SampleMatches.crb, minute: 5)
        let second = goal(SampleMatches.crb, minute: 15)
        let reply = goal(SampleMatches.nautico, minute: 25)
        let context = match(events: [first, second, reply])

        #expect(engine.goalContext(for: reply, in: context) == .reducesDeficit)
    }

    // MARK: - Scoreline

    @Test("The scoreline after a goal is announced")
    func scorelineIsAnnounced() throws {
        let scored = goal(SampleMatches.nautico, minute: 10, player: "Marquinhos")
        let narration = try #require(engine.narrate(scored, in: match(events: [scored])))

        #expect(narration.text.contains("Náutico 1"))
        #expect(narration.text.contains("CRB 0"))
    }

    @Test("An own goal credits the opposing side in the scoreline")
    func ownGoalCreditsOpponent() throws {
        let own = event(.ownGoal, minute: 30, player: "Wanderson")
        let narration = try #require(engine.narrate(own, in: match(events: [own])))

        #expect(narration.text.contains("Náutico 0"))
        #expect(narration.text.contains("CRB 1"))
    }

    @Test("Replaying a past goal reports the score at that moment, not the current one")
    func replayUsesHistoricalScore() throws {
        // Match.score says 2-1, but the first goal must still be narrated as 0-1. This is the trap
        // in reading Match.score directly instead of recomputing from the event list.
        let opener = goal(SampleMatches.crb, minute: 23, player: "Ribamar")
        let leveller = goal(SampleMatches.nautico, minute: 52)
        let winner = goal(SampleMatches.nautico, minute: 66)
        let context = match(events: [opener, leveller, winner], score: Score(home: 2, away: 1))

        let narration = try #require(engine.narrate(opener, in: context))

        #expect(narration.text.contains("Náutico 0"))
        #expect(narration.text.contains("CRB 1"))
    }

    // MARK: - Content presence

    @Test("The scorer is named")
    func scorerIsNamed() throws {
        let scored = goal(SampleMatches.nautico, minute: 52, player: "Marquinhos")
        let narration = try #require(engine.narrate(scored, in: match(events: [scored])))

        #expect(narration.text.contains("Marquinhos"))
    }

    @Test("An assist is mentioned when present")
    func assistIsMentioned() throws {
        let scored = goal(
            SampleMatches.nautico,
            minute: 52,
            player: "Marquinhos",
            assist: "Paulo Sérgio"
        )
        let narration = try #require(engine.narrate(scored, in: match(events: [scored])))

        #expect(narration.text.contains("Paulo Sérgio"))
    }

    @Test("A penalty goal never mentions an assist")
    func penaltyGoalOmitsAssist() throws {
        // Providers sometimes populate the related player on a penalty. Speaking it would credit
        // an assist on a spot kick, which does not exist.
        let scored = goal(
            SampleMatches.nautico,
            minute: 66,
            player: "Jean Carlos",
            assist: "Alguém",
            kind: .penaltyScored
        )
        let narration = try #require(engine.narrate(scored, in: match(events: [scored])))

        #expect(narration.text.contains("pênalti"))
        #expect(!narration.text.contains("Alguém"))
    }

    @Test("A sending off reports how many players are left")
    func sendingOffReportsRemainingPlayers() throws {
        let red = event(.redCard, minute: 58, player: "Wanderson")
        let narration = try #require(engine.narrate(red, in: match(events: [red])))

        #expect(narration.text.contains("dez"))
        #expect(narration.text.contains("Wanderson"))
    }

    @Test("A second sending off leaves nine players")
    func secondSendingOffLeavesNine() throws {
        let first = event(.redCard, minute: 40, player: "Wanderson")
        let second = event(.secondYellowCard, minute: 70, player: "Jean Carlos")
        let narration = try #require(engine.narrate(second, in: match(events: [first, second])))

        #expect(narration.text.contains("nove"))
    }

    @Test("A substitution names who comes off and who comes on")
    func substitutionNamesBothPlayers() throws {
        let sub = event(
            .substitution,
            minute: 61,
            team: SampleMatches.crb,
            player: "Anselmo",
            related: "Ribamar"
        )
        let narration = try #require(engine.narrate(sub, in: match(events: [sub])))

        #expect(narration.text.contains("Anselmo"))
        #expect(narration.text.contains("Ribamar"))
    }

    // MARK: - Time reference

    @Test("Stoppage time is announced as added minutes")
    func stoppageTimeIsAnnounced() throws {
        let card = MatchEvent(
            kind: .yellowCard,
            minute: 45,
            stoppageMinute: 2,
            team: SampleMatches.nautico,
            player: "Wanderson",
            relatedPlayer: nil,
            detail: nil
        )
        let narration = try #require(engine.narrate(card, in: match(events: [card])))

        #expect(narration.text.contains("acréscimos") || narration.text.contains("45 mais 2"))
    }

    @Test("The end of the first half is not narrated as the end of the match")
    func firstHalfEndIsNotFullTime() throws {
        // The event lands on minute 45, which belongs to the first half. Deriving the period from
        // the minute alone would push it into the second half and announce full time at half time.
        let end = MatchEvent(
            kind: .periodEnd,
            minute: 45,
            stoppageMinute: 2,
            team: SampleMatches.nautico,
            player: nil,
            relatedPlayer: nil,
            detail: nil
        )
        let narration = try #require(engine.narrate(end, in: match(events: [end])))

        #expect(narration.text.contains("primeiro tempo") || narration.text.contains("primeira"))
        #expect(!narration.text.contains("Fim de jogo"))
    }

    @Test("Kick-off is not prefixed with a time marker")
    func kickOffHasNoTimeMarker() throws {
        let start = event(.periodStart, minute: 0)
        let narration = try #require(engine.narrate(start, in: match(events: [start])))

        #expect(!narration.text.contains("Aos 0"))
        #expect(!narration.text.contains("Minuto 0"))
    }

    // MARK: - Silence and priority

    @Test("An unrecognised event produces no narration")
    func unknownEventIsSilent() {
        let unknown = MatchEvent(
            kind: .unknown,
            minute: 30,
            stoppageMinute: nil,
            team: SampleMatches.nautico,
            player: nil,
            relatedPlayer: nil,
            detail: "Something the provider invented"
        )

        #expect(engine.narrate(unknown, in: match(events: [unknown])) == nil)
    }

    @Test(
        "Score-changing events outrank everything else",
        arguments: [MatchEventKind.goal, .ownGoal, .penaltyScored]
    )
    func scoreChangingEventsAreCritical(kind: MatchEventKind) throws {
        let scored = goal(SampleMatches.nautico, minute: 30, kind: kind)
        let narration = try #require(engine.narrate(scored, in: match(events: [scored])))

        #expect(narration.priority == .critical)
    }

    @Test("Goals are spoken before earlier lower-priority events")
    func goalsOutrankEarlierEvents() throws {
        let sub = event(
            .substitution,
            minute: 61,
            team: SampleMatches.crb,
            player: "Anselmo",
            related: "Ribamar"
        )
        let scored = goal(SampleMatches.nautico, minute: 66, player: "Jean Carlos")
        let context = match(events: [sub, scored])

        let narrations = engine.narrate([sub, scored], in: context)

        #expect(narrations.count == 2)
        // The goal happened later but must be spoken first.
        #expect(narrations.first?.priority == .critical)
    }

    // MARK: - Determinism and variety

    @Test("The same event always produces the same sentence")
    func narrationIsDeterministic() throws {
        let scored = goal(SampleMatches.nautico, minute: 30, player: "Marquinhos")
        let context = match(events: [scored])

        let first = try #require(engine.narrate(scored, in: context))
        let second = try #require(engine.narrate(scored, in: context))

        #expect(first.text == second.text)
    }

    @Test("A fresh engine instance produces the same sentence for the same event")
    func narrationIsStableAcrossInstances() throws {
        // Guards the stable hash. Swift's own hashValue is seeded per process, and using it would
        // make a replayed moment sound different from the live one.
        let scored = goal(SampleMatches.nautico, minute: 30, player: "Marquinhos")
        let context = match(events: [scored])

        let first = try #require(TemplateNarrationEngine().narrate(scored, in: context))
        let second = try #require(TemplateNarrationEngine().narrate(scored, in: context))

        #expect(first.text == second.text)
    }

    @Test("Different events of the same kind are not narrated identically")
    func varietyAcrossEvents() {
        // Four bookings in one match must not yield four identical sentences: repetition is a real
        // defect when the interface is audio only.
        let cards = (1...4).map { index in
            event(.yellowCard, minute: index * 10, player: "Jogador \(index)")
        }
        let context = match(events: cards)

        let sentences = cards.compactMap { engine.narrate($0, in: context)?.text }
        // Strip the player name so only the phrasing is compared.
        let shapes = Set(
            zip(sentences, 1...4).map { $0.replacingOccurrences(of: "Jogador \($1)", with: "X") }
        )

        #expect(shapes.count > 1)
    }
}
