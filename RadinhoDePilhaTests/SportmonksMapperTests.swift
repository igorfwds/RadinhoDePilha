import Foundation
import Testing
@testable import RadinhoDePilha

/// Anchor for locating the test bundle, as in ``APIFootballMapperTests``.
private final class SportmonksFixtureLocator {}

/// Tests the Sportmonks adapter against a response actually returned by the vendor.
///
/// The payload in `Fixtures/` is Celtic 0×1 Rangers, Scottish Premiership, 20 September 2026,
/// captured with the same includes the provider asks for. It comes from the Scottish league
/// because that is what the free plan reaches; the wire format is the same for every league.
@Suite("Sportmonks adapter")
struct SportmonksMapperTests {
    // MARK: - Fixture loading

    private static func fixtureData(_ name: String) throws -> Data {
        if let url = Bundle(for: SportmonksFixtureLocator.self).url(
            forResource: name.replacingOccurrences(of: ".json", with: ""),
            withExtension: "json"
        ) {
            return try Data(contentsOf: url)
        }

        let sourceTree = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        return try Data(contentsOf: sourceTree.appendingPathComponent(name))
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func recorded() throws -> Match {
        let data = try Self.fixtureData("sportmonks-fixture-19722782.json")
        let fixture = try #require(
            try Self.decoder().decode(SportmonksResponse<SportmonksFixture>.self, from: data).data
        )

        return SportmonksMapper.match(from: fixture)
    }

    private func fixture(
        stateID: Int,
        periods: [SportmonksPeriod] = [],
        events: [SportmonksEvent] = []
    ) -> SportmonksFixture {
        SportmonksFixture(
            id: 1,
            leagueId: SportmonksMapper.serieBLeagueID,
            stateId: stateID,
            startingAtTimestamp: 1_791_498_600,
            participants: [
                SportmonksParticipant(
                    id: 20,
                    name: "Novorizontino",
                    imagePath: nil,
                    meta: .init(location: "away")
                ),
                SportmonksParticipant(
                    id: 10,
                    name: "Náutico",
                    imagePath: nil,
                    meta: .init(location: "home")
                )
            ],
            scores: [],
            periods: periods,
            events: events
        )
    }

    private func period(
        order: Int,
        ticking: Bool,
        countsFrom: Int,
        minutes: Int
    ) -> SportmonksPeriod {
        SportmonksPeriod(
            sortOrder: order,
            ticking: ticking,
            countsFrom: countsFrom,
            periodLength: 45,
            minutes: minutes
        )
    }

    // MARK: - Recorded match

    @Test("Home and away come from the location, not from the array order")
    func sidesFollowLocation() throws {
        let match = try recorded()

        // The payload lists Rangers, the away side, first.
        #expect(match.homeTeam.name == "Celtic")
        #expect(match.awayTeam.name == "Rangers")
    }

    @Test("The score is the current tally, not a half's")
    func scoreIsCurrent() throws {
        #expect(try recorded().score == Score(home: 0, away: 1))
    }

    @Test("A finished match is finished, at ninety minutes")
    func finishedMatch() throws {
        let match = try recorded()

        #expect(match.status == .finished)
        #expect(match.elapsedMinutes == 90)
        #expect(match.id == "19722782")
    }

    @Test("The goal is attributed to the scorer and his side")
    func goalIsMapped() throws {
        let match = try recorded()
        let goals = match.events.filter { $0.kind == .goal }

        #expect(goals.count == 1)
        #expect(goals.first?.player == "Ryan Naderi")
        #expect(goals.first?.minute == 33)
        #expect(goals.first?.team == match.awayTeam)
    }

    @Test("A substitution names who comes on first and who goes off second")
    func substitutionDirection() throws {
        let first = try #require(try recorded().events.first { $0.kind == .substitution })

        // Kasper Høgh started on the bench and Luke McCowan in the eleven, per the line-ups of
        // the same match.
        #expect(first.player == "Kasper Høgh")
        #expect(first.relatedPlayer == "Luke McCowan")
    }

    @Test("Every reported kind is recognised")
    func kindsAreCounted() throws {
        let events = try recorded().events

        // Five of the six bookings in the payload: the sixth was shown to a coach.
        #expect(events.count { $0.kind == .yellowCard } == 5)
        #expect(events.count { $0.kind == .substitution } == 10)
        #expect(events.count { $0.kind == .varDecision } == 1)
    }

    @Test("Events are chronological, bracketed by the derived period boundaries")
    func eventsAreChronological() throws {
        let events = try recorded().events
        let minutes = events.map(\.absoluteMinute)

        #expect(minutes == minutes.sorted())
        #expect(events.first?.kind == .periodStart)
        #expect(events.last?.kind == .periodEnd)
        #expect(events.count { $0.kind == .periodStart } == 2)
        #expect(events.count { $0.kind == .periodEnd } == 2)
    }

    @Test("The first half ends before the second begins")
    func halfTimeBoundariesAreInOrder() throws {
        let boundaries = try recorded().events
            .filter { $0.kind == .periodStart || $0.kind == .periodEnd }
            .map(\.kind)

        #expect(boundaries == [.periodStart, .periodEnd, .periodStart, .periodEnd])
    }

    // MARK: - Clock

    @Test("First-half stoppage does not read as the second half")
    func stoppageIsCapped() {
        let live = fixture(
            stateID: 2,
            periods: [period(order: 1, ticking: true, countsFrom: 0, minutes: 47)]
        )
        let match = SportmonksMapper.match(from: live)

        #expect(match.status == .firstHalf)
        #expect(match.elapsedMinutes == 45)
        // Only the kick-off: no end of the first half, no start of the second.
        #expect(match.events.map(\.kind) == [.periodStart])
    }

    @Test("Half-time closes the first half without opening the second")
    func halfTime() {
        let interval = fixture(
            stateID: 3,
            periods: [period(order: 1, ticking: false, countsFrom: 0, minutes: 48)]
        )
        let match = SportmonksMapper.match(from: interval)

        #expect(match.status == .halfTime)
        #expect(match.events.map(\.kind) == [.periodStart, .periodEnd])
    }

    @Test("The second half reports its running minute")
    func secondHalfMinute() {
        let live = fixture(
            stateID: 22,
            periods: [
                period(order: 1, ticking: false, countsFrom: 0, minutes: 47),
                period(order: 2, ticking: true, countsFrom: 45, minutes: 63)
            ]
        )

        #expect(SportmonksMapper.match(from: live).elapsedMinutes == 63)
    }

    @Test("A match that has not started has no clock and no events")
    func scheduled() {
        let match = SportmonksMapper.match(from: fixture(stateID: 1))

        #expect(match.status == .scheduled)
        #expect(match.elapsedMinutes == nil)
        #expect(match.events.isEmpty)
        #expect(match.competition == .brasileiraoSerieB)
        #expect(match.season == 2026)
    }

    // MARK: - Events

    @Test("A card shown to a coach is not narrated as a player's")
    func coachCardIsDropped() throws {
        // Derek McInnes, booked on the bench in the fifth minute of the recorded match.
        #expect(try !recorded().events.contains { $0.player == "Derek McInnes" })
    }

    @Test("A rescinded card is not narrated")
    func rescindedCardIsDropped() {
        let card = SportmonksEvent(
            typeId: 20,
            participantId: 10,
            playerName: "Fulano",
            relatedPlayerName: nil,
            minute: 30,
            extraMinute: nil,
            info: nil,
            addition: nil,
            sortOrder: 1,
            rescinded: true,
            coachId: nil
        )
        let match = SportmonksMapper.match(from: fixture(stateID: 2, events: [card]))

        #expect(!match.events.contains { $0.kind == .redCard })
    }

    @Test(
        "States map onto the domain",
        arguments: [
            (1, MatchStatus.scheduled), (2, .firstHalf), (3, .halfTime), (22, .secondHalf),
            (5, .finished), (18, .interrupted), (11, .suspended), (10, .postponed),
            (19, .inProgress), (999, .unknown)
        ]
    )
    func states(id: Int, expected: MatchStatus) {
        #expect(SportmonksMapper.status(fromStateID: id) == expected)
    }

    // MARK: - Club naming and example match

    @Test("Náutico gets its curated name and nickname from the vendor's spelling")
    func nauticoIsCurated() {
        let match = SportmonksMapper.match(from: fixture(stateID: 1))

        #expect(match.homeTeam.shortName == "Náutico")
        // The nickname the narration alternates with.
        #expect(match.homeTeam.nickname == "Timbu")
    }

    @Test("The crest comes from the vendor's image path")
    func crestIsMapped() throws {
        #expect(try recorded().homeTeam.crestURL?.host == "cdn.sportmonks.com")
    }
}
