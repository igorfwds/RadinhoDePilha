import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Plays derived from Sportmonks totals")
struct SportmonksPlayDerivationTests {
    private let match = SampleMatches.liveComeback

    /// Totals with two players a side, enough to tell "one changed" from "several changed".
    private func counters(
        homeCorners: Int = 0,
        awayCorners: Int = 0,
        homeFouls: Int = 0,
        awayFouls: Int = 0,
        homeOffsides: Int = 0,
        foulsCommitted: [Int: Int] = [:],
        foulsDrawn: [Int: Int] = [:],
        offsides: [Int: Int] = [:]
    ) -> SportmonksCounters {
        var counters = SportmonksCounters()
        counters.teams[SportmonksPlayDerivation.corners] = [.home: homeCorners, .away: awayCorners]
        counters.teams[SportmonksPlayDerivation.fouls] = [.home: homeFouls, .away: awayFouls]
        counters.teams[SportmonksPlayDerivation.offsides] = [.home: homeOffsides, .away: 0]
        counters.players[SportmonksPlayDerivation.fouls] = foulsCommitted
        counters.players[SportmonksPlayDerivation.foulsDrawn] = foulsDrawn
        counters.players[SportmonksPlayDerivation.offsides] = offsides
        counters.playerNames = [1: "Wanderson", 2: "Marquinhos", 3: "Ribamar", 4: "Anselmo"]
        counters.playerSides = [1: .home, 2: .home, 3: .away, 4: .away]

        return counters
    }

    private func derive(from old: SportmonksCounters, to new: SportmonksCounters) -> [MatchEvent] {
        SportmonksPlayDerivation.events(from: old, to: new, in: match)
    }

    @Test("A corner total that grows by one is a corner for that side")
    func cornerGoesToTheSideWhoseTotalGrew() {
        let events = derive(from: counters(awayCorners: 2), to: counters(awayCorners: 3))

        #expect(events.map(\.kind) == [.corner])
        #expect(events.first?.team.id == match.awayTeam.id)
    }

    @Test("Totals that did not change produce nothing")
    func unchangedTotalsAreSilent() {
        #expect(derive(from: counters(homeFouls: 5), to: counters(homeFouls: 5)).isEmpty)
    }

    @Test("A total that goes down is a correction, not a play")
    func correctionsAreIgnored() {
        #expect(derive(from: counters(homeFouls: 5), to: counters(homeFouls: 4)).isEmpty)
    }

    @Test("A foul names who committed it and who suffered it when one player changed on each side")
    func foulNamesBothPlayers() {
        let events = derive(
            from: counters(homeFouls: 3, foulsCommitted: [1: 1], foulsDrawn: [3: 0]),
            to: counters(homeFouls: 4, foulsCommitted: [1: 2], foulsDrawn: [3: 1])
        )

        #expect(events.first?.kind == .foul)
        #expect(events.first?.team.id == match.homeTeam.id)
        #expect(events.first?.player == "Wanderson")
        #expect(events.first?.relatedPlayer == "Ribamar")
    }

    @Test("A foul is left unnamed when the player totals have not caught up")
    func foulWithoutPlayerTotalsHasNoNames() {
        let events = derive(from: counters(awayFouls: 1), to: counters(awayFouls: 2))

        #expect(events.first?.kind == .foul)
        #expect(events.first?.player == nil)
        #expect(events.first?.relatedPlayer == nil)
    }

    @Test("A foul is left unnamed when two players changed at once, rather than guessed")
    func ambiguousFoulHasNoOffender() {
        let events = derive(
            from: counters(homeFouls: 3, foulsCommitted: [1: 1, 2: 0]),
            to: counters(homeFouls: 4, foulsCommitted: [1: 2, 2: 1])
        )

        #expect(events.first?.player == nil)
    }

    @Test("An offside names the player whose own total grew")
    func offsideNamesThePlayer() {
        let events = derive(
            from: counters(homeOffsides: 0, offsides: [2: 0]),
            to: counters(homeOffsides: 1, offsides: [2: 1])
        )

        #expect(events.first?.kind == .offside)
        #expect(events.first?.player == "Marquinhos")
    }

    @Test("Two corners in the same minute are two different events")
    func sameMinutePlaysHaveDistinctIdentifiers() {
        let events = derive(from: counters(homeCorners: 1), to: counters(homeCorners: 3))

        #expect(events.count == 2)
        #expect(Set(events.map(\.id)).count == 2)
    }

    @Test("A large jump is treated as a correction and capped")
    func burstsAreCapped() {
        let events = derive(from: counters(homeFouls: 2), to: counters(homeFouls: 12))

        #expect(events.count == SportmonksPlayDerivation.burstLimit)
    }

    @Test("The same play keeps its identifier on a later request")
    func identifiersAreStable() {
        let first = derive(from: counters(homeCorners: 1), to: counters(homeCorners: 2))
        let again = derive(from: counters(homeCorners: 1), to: counters(homeCorners: 2))

        #expect(first.map(\.id) == again.map(\.id))
    }

    @Test("Events reported one by one keep the identifier they always had")
    func reportedEventsKeepTheirIdentifier() {
        #expect(match.events[1].id == "23|0|goal|crb|Ribamar")
    }

    // MARK: - Narration

    @Test("Each derived play is narrated in a few words")
    func derivedPlaysAreNarrated() throws {
        let engine = TemplateNarrationEngine()
        let foul = try #require(
            derive(
                from: counters(homeFouls: 3, foulsCommitted: [1: 1], foulsDrawn: [3: 0]),
                to: counters(homeFouls: 4, foulsCommitted: [1: 2], foulsDrawn: [3: 1])
            ).first
        )

        let text = try #require(engine.narrate(foul, in: match)?.text)

        #expect(text.hasPrefix("Falta do "))
        #expect(text.hasSuffix("Wanderson em Ribamar."))
    }

    @Test("Frequent plays carry no sound or vibration")
    func derivedPlaysHaveNoCue() throws {
        let corner = try #require(
            derive(from: counters(homeCorners: 0), to: counters(homeCorners: 1)).first
        )

        #expect(EventCue(event: corner, in: match) == nil)
    }
}
