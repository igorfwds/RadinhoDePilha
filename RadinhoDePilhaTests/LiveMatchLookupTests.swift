import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Spoken dates")
struct SpokenDateTests {
    /// Fixed reference so the tests do not drift with the calendar.
    private let timeZone = TimeZone(identifier: "America/Recife")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func subject() -> SpokenDate {
        SpokenDate(locale: Locale(identifier: "pt_BR"), timeZone: timeZone)
    }

    @Test("A time on the hour is spoken without minutes")
    func wholeHourOmitsMinutes() {
        // "às 16:00" would be read as a pair of numbers with a symbol between them.
        #expect(subject().timePhrase(for: date("2026-09-24T16:00:00-03:00")) == "às 16 horas")
    }

    @Test("A time with minutes is spoken as words, not as a clock reading")
    func minutesAreSpokenAsWords() {
        #expect(subject().timePhrase(for: date("2026-09-24T20:30:00-03:00")) == "às 20 e 30")
    }

    @Test("Today and tomorrow replace the weekday")
    func relativeDaysWin() {
        let subject = subject()
        let now = date("2026-09-24T10:00:00-03:00")

        #expect(subject.dayPhrase(for: date("2026-09-24T20:30:00-03:00"), relativeTo: now) == "hoje")
        #expect(subject.dayPhrase(for: date("2026-09-25T20:30:00-03:00"), relativeTo: now) == "amanhã")
    }

    @Test("A day within the week is named by weekday and date")
    func weekdayIsNamed() {
        let phrase = subject().dayPhrase(
            for: date("2026-09-26T20:30:00-03:00"),
            relativeTo: date("2026-09-24T10:00:00-03:00")
        )

        // Wording is asserted loosely: the month name comes from the locale, and pinning the exact
        // string would be testing Foundation rather than this type.
        #expect(phrase.contains("26"))
        #expect(phrase.contains("setembro"))
        #expect(!phrase.contains("/"))
    }

    @Test("Nothing spoken contains a separator the synthesiser would read aloud")
    func noSymbolsInSpokenForm() {
        let phrase = subject().phrase(
            for: date("2026-09-26T20:30:00-03:00"),
            relativeTo: date("2026-09-24T10:00:00-03:00")
        )

        #expect(!phrase.contains("/"))
        #expect(!phrase.contains(":"))
    }
}

@Suite("Live match lookup")
@MainActor
struct LiveMatchFinderTests {
    private func finder(
        provider: MatchDataProvider,
        speech: SpeechServiceSpy = SpeechServiceSpy()
    ) -> (LiveMatchFinder, SpeechServiceSpy) {
        (
            LiveMatchFinder(
                provider: provider,
                speech: speech,
                teamID: SampleMatches.nautico.id
            ),
            speech
        )
    }

    @Test("A live Náutico match is found and announced")
    func liveMatchIsFound() async {
        // The sample provider's live match is Náutico's, and its team id is the one being followed.
        let match = SampleMatches.liveComeback
        let provider = ScriptedMatchDataProvider(states: [match])
        let (subject, spy) = finder(
            provider: provider,
            speech: SpeechServiceSpy()
        )

        await subject.search(season: match.season)

        #expect(subject.outcome == .live(match))
        // Announced aloud, not only shown: the listener may not be able to read the screen.
        #expect(await !spy.spokenText.isEmpty)
    }

    @Test("With nothing under way, the absence is announced")
    func idleIsAnnounced() async {
        let provider = ScriptedMatchDataProvider(states: [])
        let (subject, spy) = finder(provider: provider)

        await subject.search(season: 2026)

        #expect(subject.outcome == .idle(next: nil))
        #expect(await spy.spokenText.contains { $0.contains("Não há partida") })
    }

    @Test("A failed lookup says so instead of failing silently")
    func failureIsAnnounced() async {
        let provider = FailingMatchDataProvider(error: .quotaExceeded)
        let (subject, spy) = finder(provider: provider)

        await subject.search(season: 2026)

        #expect(subject.outcome == .failed(MatchDataError.quotaExceeded.userFacingMessage))
        #expect(await !spy.spokenText.isEmpty)
    }

    @Test("The next fixture is named with day and time, spoken as words")
    func nextFixtureIsSpelledOut() {
        let (subject, _) = finder(provider: ScriptedMatchDataProvider(states: []))

        let next = Match(
            id: "next",
            competition: .brasileiraoSerieB,
            season: 2026,
            homeTeam: SampleMatches.crb,
            awayTeam: SampleMatches.nautico,
            kickoff: Date(timeIntervalSince1970: 1_790_000_000),
            status: .scheduled,
            elapsedMinutes: nil,
            score: .goalless,
            events: []
        )

        let announcement = subject.idleAnnouncement(next: next)

        #expect(announcement.contains("Não há partida"))
        // Names the opponent, which is Náutico's rival in this fixture rather than Náutico itself.
        #expect(announcement.contains("CRB"))
        #expect(!announcement.contains("/"))
        #expect(!announcement.contains(":"))
    }
}
