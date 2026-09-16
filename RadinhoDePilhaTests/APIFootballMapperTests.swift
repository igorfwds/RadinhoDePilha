import Foundation
import Testing
@testable import RadinhoDePilha

/// Anchor for locating the test bundle.
///
/// Swift Testing has no `XCTestCase` to hand to `Bundle(for:)`, so an empty class is the way to
/// name the bundle these tests were compiled into.
private final class FixtureLocator {}

/// Tests the vendor adapter against responses actually returned by API-Football.
///
/// The payloads in `Fixtures/` were captured from the live API for Náutico in Série B 2022, the
/// most recent season the free plan exposes. Testing against recorded responses rather than
/// hand-written JSON is the point: every defect these tests guard against was present in the real
/// data and absent from the documentation.
@Suite("API-Football adapter")
struct APIFootballMapperTests {
    // MARK: - Fixture loading

    /// Reads a recorded payload, from the test bundle when it was copied in and from the source
    /// tree otherwise.
    ///
    /// The bundle comes first because it is the only one that works on a real device: `#filePath`
    /// points at the developer's Mac, which an iPhone cannot reach. The filesystem fallback keeps
    /// the tests runnable if the resource is ever dropped from the target.
    private static func fixtureData(_ name: String) throws -> Data {
        if let url = Bundle(for: FixtureLocator.self).url(
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
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fixtures() throws -> [APIFootballFixtureItem] {
        let data = try Self.fixtureData("fixtures-nautico-serieb-2022.json")
        return try Self.decoder()
            .decode(APIFootballResponse<[APIFootballFixtureItem]>.self, from: data)
            .response
    }

    private func events() throws -> [APIFootballEvent] {
        let data = try Self.fixtureData("events-838946.json")
        return try Self.decoder()
            .decode(APIFootballResponse<[APIFootballEvent]>.self, from: data)
            .response
    }

    /// Náutico 4×3 Tombense, round 33 of Série B 2022. Chosen for covering goals, a penalty, a
    /// VAR review, cards, substitutions and stoppage time in a single match.
    private func showcaseFixture() throws -> APIFootballFixtureItem {
        let all = try fixtures()
        return try #require(all.first { $0.fixture.id == 838946 })
    }

    // MARK: - Decoding

    @Test("The recorded season decodes without error")
    func seasonDecodes() throws {
        let all = try fixtures()

        #expect(all.count == 38)
    }

    @Test("An empty errors array decodes as no errors")
    func emptyErrorsDecode() throws {
        let data = try Self.fixtureData("fixtures-nautico-serieb-2022.json")
        let envelope = try Self.decoder()
            .decode(APIFootballResponse<[APIFootballFixtureItem]>.self, from: data)

        // The vendor types this field as [] when empty and as an object otherwise.
        #expect(envelope.errors.isEmpty)
        #expect(envelope.errors.planRestriction == nil)
    }

    @Test("A plan restriction decodes from the object form of errors")
    func planRestrictionDecodes() throws {
        // Exactly what the free plan returns when asked for season 2026.
        let json = """
        {"response": [], "results": 0,
         "errors": {"plan": "Free plans do not have access to this season, try from 2022 to 2024."}}
        """
        let envelope = try Self.decoder()
            .decode(APIFootballResponse<[APIFootballFixtureItem]>.self, from: Data(json.utf8))

        #expect(!envelope.errors.isEmpty)
        #expect(envelope.errors.planRestriction?.contains("2022 to 2024") == true)
    }

    // MARK: - Match mapping

    @Test("A fixture maps onto the domain with the right score and status")
    func fixtureMapsToMatch() throws {
        let match = APIFootballMapper.match(from: try showcaseFixture())

        #expect(match.id == "838946")
        #expect(match.competition == .brasileiraoSerieB)
        #expect(match.season == 2022)
        #expect(match.score == Score(home: 4, away: 3))
        #expect(match.status == .finished)
        #expect(!match.isLive)
    }

    @Test("Club names are restored with their diacritics")
    func clubNamesAreCorrected() throws {
        // The vendor sends "Nautico Recife". Spoken aloud, the missing accent changes the word.
        let match = APIFootballMapper.match(from: try showcaseFixture())

        #expect(match.homeTeam.shortName == "Náutico")
        #expect(match.homeTeam.name == "Clube Náutico Capibaribe")
        #expect(match.homeTeam.nickname == "Timbu")
    }

    @Test("A match in play keeps polling even when the minute is unknown")
    func inProgressStaysLive() {
        // The defect: `LIVE` means in play without a known minute, and treating it as unknown made
        // `isLive` false, which stopped the loop mid-match.
        #expect(APIFootballMapper.status(from: "LIVE").isLive)
        #expect(APIFootballMapper.status(from: "INT").isLive)
        #expect(APIFootballMapper.status(from: "SUSP").isLive)
        // Play is not actually happening in the halted ones, though.
        #expect(!APIFootballMapper.status(from: "INT").isBallInPlay)
        #expect(APIFootballMapper.status(from: "LIVE").isBallInPlay)
    }

    @Test("Matches decided or ended off the pitch stop the loop")
    func endedStatesStopPolling() {
        #expect(!APIFootballMapper.status(from: "ABD").isLive)
        #expect(!APIFootballMapper.status(from: "WO").isLive)
        #expect(!APIFootballMapper.status(from: "AWD").isLive)
    }

    @Test("An unknown club still gets a usable name")
    func unknownClubFallsBack() {
        let team = ClubDirectory.team(id: 999_999, vendorName: "Clube Desconhecido")

        #expect(team.shortName == "Clube Desconhecido")
        #expect(team.nickname == nil)
    }

    @Test(
        "Lookup ignores accents and case, since the vendor is inconsistent about both",
        arguments: ["Criciuma", "Criciúma", "CRICIUMA", "  criciúma  "]
    )
    func lookupIsAccentAndCaseInsensitive(vendorName: String) {
        // Real responses contain "Criciuma" stripped but "Confiança" and "Ferroviária" intact,
        // so both spellings of the same club have to resolve.
        #expect(ClubDirectory.team(id: 140, vendorName: vendorName).shortName == "Criciúma")
    }

    @Test("Every club in the national divisions is covered by the directory")
    func nationalDivisionsAreCovered() throws {
        // Guards the narration against a club arriving unspelled. The fallback keeps the app
        // working, but "Gremio" spoken aloud is not "Grêmio".
        let files = [
            "teams-serieA2024.json",
            "teams-serieB2024.json",
            "teams-serieB2022.json",
            "teams-serieC2024.json"
        ]

        var missing: [String] = []

        for file in files {
            let data = try Self.fixtureData(file)
            let items = try Self.decoder()
                .decode(APIFootballResponse<[APIFootballTeamItem]>.self, from: data)
                .response

            for item in items where !ClubDirectory.knows(item.team.name) {
                missing.append(item.team.name)
            }
        }

        #expect(missing.isEmpty, "clubes fora do dicionário: \(Set(missing).sorted())")
    }

    // MARK: - Status

    @Test(
        "Vendor status codes map onto the domain",
        arguments: [
            ("NS", MatchStatus.scheduled),
            ("1H", .firstHalf),
            ("HT", .halfTime),
            ("2H", .secondHalf),
            ("ET", .extraTime),
            ("FT", .finished),
            ("AET", .finished),
            ("PEN", .finished),
            ("PST", .postponed),
            ("CANC", .cancelled),
            ("BT", .breakTime),
            ("P", .penaltyShootout),
            // Used to fall through to `unknown`, which stops the polling loop, on a match that is
            // being played. The worst possible moment to go quiet.
            ("LIVE", .inProgress),
            ("INT", .interrupted),
            ("SUSP", .suspended),
            ("ABD", .abandoned),
            ("WO", .awarded),
            ("XX", .unknown)
        ]
    )
    func statusMaps(code: String, expected: MatchStatus) {
        #expect(APIFootballMapper.status(from: code) == expected)
    }

    // MARK: - Event kinds

    @Test(
        "Event type and detail map onto the domain",
        arguments: [
            ("Goal", "Normal Goal", MatchEventKind.goal),
            ("Goal", "Own Goal", .ownGoal),
            ("Goal", "Penalty", .penaltyScored),
            ("Goal", "Missed Penalty", .penaltyMissed),
            ("Card", "Yellow Card", .yellowCard),
            ("Card", "Red Card", .redCard),
            ("Card", "Second Yellow card", .secondYellowCard),
            ("Var", "Penalty awarded", .varDecision),
            ("Var", "Goal cancelled", .varDecision)
        ]
    )
    func eventKindMaps(type: String, detail: String, expected: MatchEventKind) {
        #expect(APIFootballMapper.kind(type: type, detail: detail) == expected)
    }

    @Test("Substitution type is matched regardless of case")
    func substitutionCaseIsIgnored() {
        // The documentation says "Subst"; the API sends "subst".
        #expect(APIFootballMapper.kind(type: "subst", detail: "Substitution 1") == .substitution)
        #expect(APIFootballMapper.kind(type: "Subst", detail: "Substitution 1") == .substitution)
    }

    // MARK: - The substitution swap

    @Test("A substitution names the player coming on, not the one going off")
    func substitutionPlayersAreSwapped() throws {
        // The defect this guards against would reverse every substitution the app announces.
        // In the recorded match, Keké is booked at 58' and substituted in the same minute, so
        // Keké is unambiguously the player leaving the pitch, and the vendor puts him in
        // `player`, which the domain reserves for whoever comes on.
        let match = APIFootballMapper.match(from: try showcaseFixture(), events: try events())

        let substitution = try #require(
            match.events.first { $0.kind == .substitution && $0.relatedPlayer == "Keké" }
        )

        #expect(substitution.player == "Caíque")       // came on
        #expect(substitution.relatedPlayer == "Keké")  // went off
    }

    @Test("Goals keep scorer and assist in their documented places")
    func goalKeepsScorerAndAssist() throws {
        let match = APIFootballMapper.match(from: try showcaseFixture(), events: try events())

        let opener = try #require(match.events.first { $0.kind == .goal && $0.minute == 11 })

        #expect(opener.player == "Kleiton")
        #expect(opener.relatedPlayer == "David")
    }

    // MARK: - Ordering

    @Test("Events come out in the order they happened")
    func eventsAreChronological() throws {
        // The recorded payload lists 45+3 before 45+1. Match promises chronological order, and
        // the narration's running score depends on it.
        let match = APIFootballMapper.match(from: try showcaseFixture(), events: try events())

        let keys = match.events.map { $0.minute * 100 + ($0.stoppageMinute ?? 0) }

        #expect(keys == keys.sorted())
    }

    @Test("The raw payload really is out of order, so the sort is not decorative")
    func rawPayloadIsUnordered() throws {
        let raw = try events().map { $0.time.elapsed * 100 + ($0.time.extra ?? 0) }

        #expect(raw != raw.sorted())
    }

    // MARK: - Derived period boundaries

    @Test("Kick-off and final whistle are synthesised, since the vendor omits them")
    func periodBoundariesAreDerived() throws {
        let match = APIFootballMapper.match(from: try showcaseFixture(), events: try events())

        let starts = match.events.filter { $0.kind == .periodStart }
        let ends = match.events.filter { $0.kind == .periodEnd }

        #expect(starts.count == 2)  // both halves
        #expect(ends.count == 2)
        #expect(match.events.first?.kind == .periodStart)
        #expect(match.events.last?.kind == .periodEnd)
    }

    @Test("A match yet to start has no period events at all")
    func scheduledMatchHasNoBoundaries() throws {
        let all = try fixtures()
        let scheduled = APIFootballMapper.match(from: try #require(all.first))

        let notStarted = Match(
            id: scheduled.id,
            competition: scheduled.competition,
            season: scheduled.season,
            homeTeam: scheduled.homeTeam,
            awayTeam: scheduled.awayTeam,
            kickoff: scheduled.kickoff,
            status: .scheduled,
            elapsedMinutes: nil,
            score: .goalless,
            events: []
        )

        #expect(APIFootballMapper.periodEvents(for: notStarted).isEmpty)
    }

    @Test("A match at half-time has kicked off and ended one period")
    func halfTimeHasOneEnding() throws {
        let base = APIFootballMapper.match(from: try showcaseFixture())
        let atHalfTime = Match(
            id: base.id,
            competition: base.competition,
            season: base.season,
            homeTeam: base.homeTeam,
            awayTeam: base.awayTeam,
            kickoff: base.kickoff,
            status: .halfTime,
            elapsedMinutes: 45,
            score: base.score,
            events: []
        )

        let derived = APIFootballMapper.periodEvents(for: atHalfTime)

        #expect(derived.filter { $0.kind == .periodStart }.count == 1)
        #expect(derived.filter { $0.kind == .periodEnd }.count == 1)
    }

    // MARK: - End to end

    @Test("The recorded match narrates from first whistle to last")
    func recordedMatchNarratesEndToEnd() throws {
        // The real payoff: vendor JSON in, spoken Portuguese out, with nothing hand-written in
        // between.
        let match = APIFootballMapper.match(from: try showcaseFixture(), events: try events())
        let engine = TemplateNarrationEngine()

        let narrations = match.events.compactMap { engine.narrate($0, in: match) }

        #expect(narrations.count >= 20)
        #expect(narrations.allSatisfy { !$0.text.isEmpty })

        // The comeback wording depends on the running score being right, which in turn depends
        // on the events being in order.
        let joined = narrations.map(\.text).joined(separator: " ")
        #expect(joined.contains("Náutico"))
        #expect(joined.contains("Tombense"))
    }
}
