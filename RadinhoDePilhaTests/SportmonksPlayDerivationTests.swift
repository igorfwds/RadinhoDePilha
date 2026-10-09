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

    @Test("With two offenders at once, no victim is guessed for either")
    func simultaneousOffendersGetNoVictim() {
        let events = derive(
            from: counters(homeFouls: 3, foulsCommitted: [1: 1, 2: 0], foulsDrawn: [3: 0]),
            to: counters(homeFouls: 4, foulsCommitted: [1: 2, 2: 1], foulsDrawn: [3: 1])
        )

        #expect(events.first?.kind == .foul)
        #expect(events.first?.relatedPlayer == nil)
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

    // MARK: - Names that arrive separately

    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("A foul is announced at once, and its players are named when their totals catch up")
    func namesFollowAnUnnamedFoul() {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(homeFouls: 3, foulsCommitted: [1: 1]), in: match, at: start)

        let atOnce = ledger.advance(
            to: counters(homeFouls: 4, foulsCommitted: [1: 1]),
            in: match,
            at: start.addingTimeInterval(4)
        )
        let later = ledger.advance(
            to: counters(homeFouls: 4, foulsCommitted: [1: 2], foulsDrawn: [3: 1]),
            in: match,
            at: start.addingTimeInterval(35)
        )

        #expect(atOnce.map(\.kind) == [.foul])
        #expect(atOnce.first?.player == nil)
        #expect(later.map(\.kind) == [.foulAttribution])
        #expect(later.first?.player == "Wanderson")
        #expect(later.first?.relatedPlayer == "Ribamar")
        #expect(later.first?.team.id == match.homeTeam.id)
    }

    @Test("Names that arrive before the team total are kept for the foul they belong to")
    func earlyNamesAreUsedWhenTheFoulArrives() {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(awayFouls: 1), in: match, at: start)

        let early = ledger.advance(
            to: counters(awayFouls: 1, foulsCommitted: [3: 1], foulsDrawn: [1: 1]),
            in: match,
            at: start.addingTimeInterval(4)
        )
        let foul = ledger.advance(
            to: counters(awayFouls: 2, foulsCommitted: [3: 1], foulsDrawn: [1: 1]),
            in: match,
            at: start.addingTimeInterval(34)
        )

        #expect(early.isEmpty)
        #expect(foul.map(\.kind) == [.foul])
        #expect(foul.first?.player == "Ribamar")
        #expect(foul.first?.relatedPlayer == "Wanderson")
    }

    @Test("A foul that never gets its names is not named after a later one")
    func staleFoulsStopWaitingForNames() {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(homeFouls: 3), in: match, at: start)
        _ = ledger.advance(to: counters(homeFouls: 4), in: match, at: start.addingTimeInterval(4))

        // Kept alive with unchanged totals, past the time names are expected within.
        var clock = start.addingTimeInterval(4)
        while clock < start.addingTimeInterval(SportmonksPlayLedger.namesExpectedWithin + 40) {
            clock = clock.addingTimeInterval(30)
            _ = ledger.advance(to: counters(homeFouls: 4), in: match, at: clock)
        }

        let late = ledger.advance(
            to: counters(homeFouls: 4, foulsCommitted: [1: 1]),
            in: match,
            at: clock.addingTimeInterval(4)
        )

        #expect(late.isEmpty)
    }

    @Test("An offside is completed with its player the same way")
    func offsideIsCompletedLater() {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(homeOffsides: 0), in: match, at: start)
        _ = ledger.advance(
            to: counters(homeOffsides: 1),
            in: match,
            at: start.addingTimeInterval(4)
        )

        let later = ledger.advance(
            to: counters(homeOffsides: 1, offsides: [2: 1]),
            in: match,
            at: start.addingTimeInterval(40)
        )

        #expect(later.map(\.kind) == [.offsideAttribution])
        #expect(later.first?.player == "Marquinhos")
    }

    @Test("After a long gap without data, what changed meanwhile is not narrated as new")
    func aLongGapResetsTheBaseline() {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(homeCorners: 1, homeFouls: 2), in: match, at: start)

        let afterOutage = ledger.advance(
            to: counters(homeCorners: 3, homeFouls: 6),
            in: match,
            at: start.addingTimeInterval(SportmonksPlayLedger.baselineExpiresAfter + 30)
        )
        let next = ledger.advance(
            to: counters(homeCorners: 4, homeFouls: 6),
            in: match,
            at: start.addingTimeInterval(SportmonksPlayLedger.baselineExpiresAfter + 34)
        )

        #expect(afterOutage.isEmpty)
        #expect(next.map(\.kind) == [.corner])
    }

    @Test("The sentence that names the players says which side the foul was by")
    func attributionIsNarrated() throws {
        var ledger = SportmonksPlayLedger()
        _ = ledger.advance(to: counters(homeFouls: 3, foulsCommitted: [1: 1]), in: match, at: start)
        _ = ledger.advance(to: counters(homeFouls: 4, foulsCommitted: [1: 1]), in: match, at: start)

        let attribution = try #require(
            ledger.advance(
                to: counters(homeFouls: 4, foulsCommitted: [1: 2], foulsDrawn: [3: 1]),
                in: match,
                at: start.addingTimeInterval(30)
            ).first
        )

        let text = try #require(TemplateNarrationEngine().narrate(attribution, in: match)?.text)

        #expect(text.hasPrefix("A falta "))
        #expect(text.hasSuffix(" foi de Wanderson, em Ribamar, do CRB."))
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

        // The side may be called by its name or its nickname, so only the fixed parts are checked.
        #expect(text.hasPrefix("Falta do "))
        #expect(text.hasSuffix(". Wanderson em Ribamar, do CRB."))
    }

    @Test("Frequent plays carry no sound or vibration")
    func derivedPlaysHaveNoCue() throws {
        let corner = try #require(
            derive(from: counters(homeCorners: 0), to: counters(homeCorners: 1)).first
        )

        #expect(EventCue(event: corner, in: match) == nil)
    }
}
