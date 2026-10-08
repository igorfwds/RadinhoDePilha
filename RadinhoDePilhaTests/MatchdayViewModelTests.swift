import Foundation
import Testing
@testable import RadinhoDePilha

/// Answers schedule questions from fixed values.
actor StubScheduleProvider: MatchScheduleProvider {
    private let last: Match?
    private let next: Match?
    private let error: MatchDataError?

    private(set) var requests = 0

    init(last: Match? = nil, next: Match? = nil, error: MatchDataError? = nil) {
        self.last = last
        self.next = next
        self.error = error
    }

    func lastMatch(forTeam teamID: String) async throws -> Match? {
        requests += 1
        if let error { throw error }
        return last
    }

    func nextMatch(forTeam teamID: String) async throws -> Match? {
        requests += 1
        if let error { throw error }
        return next
    }
}

@Suite("Matchday")
@MainActor
struct MatchdayViewModelTests {
    /// A fixed "now", so countdowns do not drift with the wall clock.
    private nonisolated static let reference = Date(timeIntervalSince1970: 1_790_000_000)

    private nonisolated static let timeZone = TimeZone(identifier: "America/Recife")!

    /// The sample Náutico match, restated with a given status and kick-off.
    private func fixture(_ status: MatchStatus, kickoff: Date, id: String = "hoje") -> Match {
        let base = SampleMatches.liveComeback

        return Match(
            id: id,
            competition: .brasileiraoSerieB,
            season: 2026,
            homeTeam: base.homeTeam,
            awayTeam: base.awayTeam,
            kickoff: kickoff,
            status: status,
            elapsedMinutes: status.isLive ? 1 : nil,
            score: .goalless,
            events: []
        )
    }

    private func subject(
        provider: MatchDataProvider,
        schedule: MatchScheduleProvider,
        speech: SpeechServiceSpy = SpeechServiceSpy()
    ) -> (MatchdayViewModel, SpeechServiceSpy) {
        (
            MatchdayViewModel(
                provider: provider,
                schedule: schedule,
                speech: speech,
                teamID: SampleMatches.nautico.id,
                dates: SpokenDate(locale: Locale(identifier: "pt_BR"), timeZone: Self.timeZone),
                now: { Self.reference },
                kickoffPollInterval: .milliseconds(10),
                countdownStep: .milliseconds(10)
            ),
            speech
        )
    }

    // MARK: - Opening

    @Test("A match in progress goes straight to narration, without speaking")
    func liveMatchIsFollowed() async {
        let live = fixture(.firstHalf, kickoff: Self.reference.addingTimeInterval(-600))
        let (viewModel, spy) = subject(
            provider: ScriptedMatchDataProvider(states: [live]),
            schedule: StubScheduleProvider()
        )

        await viewModel.load()

        // No introduction: opening the app is not a request to start talking.
        #expect(viewModel.phase == .live(live, introduction: nil))
        #expect(await spy.spokenText.isEmpty)
    }

    @Test("With nothing live, the last and the next match are shown")
    func upcomingShowsLastAndNext() async {
        let last = fixture(.finished, kickoff: Self.reference.addingTimeInterval(-7 * 86_400), id: "ontem")
        let next = fixture(.scheduled, kickoff: Self.reference.addingTimeInterval(2 * 3_600 + 14 * 60))
        let (viewModel, spy) = subject(
            provider: ScriptedMatchDataProvider(states: []),
            schedule: StubScheduleProvider(last: last, next: next)
        )

        await viewModel.load()
        viewModel.stop()

        #expect(viewModel.phase == .upcoming(next: next, last: last))
        // Opening is silent, whatever it finds.
        #expect(await spy.spokenText.isEmpty)
    }

    @Test("A scheduled match in the live list is not mistaken for a live one")
    func scheduledMatchIsNotLive() async {
        let next = fixture(.scheduled, kickoff: Self.reference.addingTimeInterval(3_600))
        let (viewModel, _) = subject(
            provider: ScriptedMatchDataProvider(states: [next]),
            schedule: StubScheduleProvider(next: next)
        )

        await viewModel.load()
        viewModel.stop()

        #expect(viewModel.phase == .upcoming(next: next, last: nil))
    }

    @Test("With nothing scheduled, the last result is still shown")
    func noUpcomingKeepsLast() async {
        let last = fixture(.finished, kickoff: Self.reference.addingTimeInterval(-86_400), id: "ontem")
        let (viewModel, _) = subject(
            provider: ScriptedMatchDataProvider(states: []),
            schedule: StubScheduleProvider(last: last)
        )

        await viewModel.load()

        #expect(viewModel.phase == .noUpcoming(last: last))
    }

    @Test("A failed lookup is shown as such, with the reason")
    func failureIsShown() async {
        let (viewModel, _) = subject(
            provider: FailingMatchDataProvider(error: .quotaExceeded),
            schedule: StubScheduleProvider()
        )

        await viewModel.load()

        #expect(viewModel.phase == .failed(MatchDataError.quotaExceeded.userFacingMessage))
    }

    // MARK: - Kick-off

    @Test("At kick-off time it waits, then starts narration once the status turns live")
    func scheduledTurnsLive() async {
        // The vendor sometimes lags a minute or two behind the real kick-off, so the first polls
        // still see the match as not started.
        let kickoff = Self.reference.addingTimeInterval(-5)
        let scheduled = fixture(.scheduled, kickoff: kickoff)
        let started = fixture(.firstHalf, kickoff: kickoff)

        let provider = ScriptedMatchDataProvider(states: [scheduled, scheduled, started])
        let (viewModel, spy) = subject(
            provider: provider,
            schedule: StubScheduleProvider(next: scheduled)
        )

        await viewModel.load()
        await waitUntil { await MainActor.run { viewModel.featuredMatch?.isLive == true } }

        #expect(viewModel.phase == .live(started, introduction: "A partida começou."))
        // The wait itself was announced, since the screen showed it.
        #expect(await spy.spokenText.contains { $0.contains("Aguardando o início") })
    }

    @Test("While the status lags, the screen says it is waiting")
    func lagShowsAwaiting() async {
        let kickoff = Self.reference.addingTimeInterval(-5)
        let scheduled = fixture(.scheduled, kickoff: kickoff)
        let (viewModel, _) = subject(
            provider: ScriptedMatchDataProvider(states: [scheduled]),
            schedule: StubScheduleProvider(next: scheduled)
        )

        await viewModel.load()
        await waitUntil {
            await MainActor.run {
                if case .awaitingKickoff = viewModel.phase { true } else { false }
            }
        }
        viewModel.stop()

        #expect(viewModel.phase == .awaitingKickoff(next: scheduled, last: nil))
    }

    @Test("Before kick-off, nothing beyond the three opening requests is made")
    func countdownCostsNoRequests() async throws {
        // Quota matters: on match days the live narration is already polling every 15 seconds.
        let next = fixture(.scheduled, kickoff: Self.reference.addingTimeInterval(3_600))
        let provider = ScriptedMatchDataProvider(states: [])
        let schedule = StubScheduleProvider(next: next)
        let (viewModel, _) = subject(provider: provider, schedule: schedule)

        await viewModel.load()
        try await Task.sleep(for: .milliseconds(100))
        viewModel.stop()

        #expect(await schedule.requests == 2)
        #expect(await provider.matchRequests == 0)
    }

    // MARK: - Speech on request

    @Test("Asking how long is left names the teams, the day and the time remaining")
    func timeRemainingIsSpoken() async throws {
        let next = fixture(.scheduled, kickoff: Self.reference.addingTimeInterval(2 * 3_600 + 14 * 60))
        let (viewModel, spy) = subject(
            provider: ScriptedMatchDataProvider(states: []),
            schedule: StubScheduleProvider(next: next)
        )

        await viewModel.load()
        viewModel.stop()
        await viewModel.speakTimeRemaining()

        let spoken = try #require(await spy.interruptingText.last)
        #expect(spoken.hasPrefix("Faltam 2 horas e 14 minutos"))
        #expect(spoken.contains("Náutico e CRB"))
        #expect(!spoken.contains(":"))
    }

    @Test("The countdown label is by the minute, never by the second")
    func countdownLabelIsApproximate() async {
        let next = fixture(.scheduled, kickoff: Self.reference.addingTimeInterval(2 * 3_600 + 14 * 60 + 37))
        let (viewModel, _) = subject(
            provider: ScriptedMatchDataProvider(states: []),
            schedule: StubScheduleProvider(next: next)
        )

        await viewModel.load()
        viewModel.stop()

        let label = viewModel.countdownLabel(at: Self.reference)
        #expect(label == "Faltam 2 horas e 14 minutos")
        #expect(!label.contains("segundo"))
    }

    @Test("The last result is spoken with the score")
    func lastResultIsSpoken() async throws {
        let last = fixture(.finished, kickoff: Self.reference.addingTimeInterval(-3 * 86_400), id: "ontem")
        let (viewModel, spy) = subject(
            provider: ScriptedMatchDataProvider(states: []),
            schedule: StubScheduleProvider(last: last)
        )

        await viewModel.load()
        await viewModel.speakLastResult()

        let spoken = try #require(await spy.interruptingText.last)
        #expect(spoken.hasPrefix("Último jogo: Náutico 0, CRB 0"))
    }
}

@Suite("Time remaining, spoken")
struct RemainingTimeTests {
    private let subject = SpokenDate(
        locale: Locale(identifier: "pt_BR"),
        timeZone: TimeZone(identifier: "America/Recife")!
    )
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func remaining(_ seconds: TimeInterval) -> String {
        subject.remainingSentence(until: now.addingTimeInterval(seconds), from: now)
    }

    @Test("Hours and minutes, approximately")
    func hoursAndMinutes() {
        #expect(remaining(2 * 3_600 + 14 * 60 + 59) == "Faltam 2 horas e 14 minutos.")
    }

    @Test("Days and hours far out, without minutes")
    func daysAndHours() {
        #expect(remaining(3 * 86_400 + 4 * 3_600 + 30 * 60) == "Faltam 3 dias e 4 horas.")
    }

    @Test("Singular when the whole remainder is one unit of one")
    func singular() {
        #expect(remaining(60) == "Falta 1 minuto.")
        #expect(remaining(3_600) == "Falta 1 hora.")
    }

    @Test("Zero parts are left out")
    func zeroPartsOmitted() {
        #expect(remaining(2 * 3_600) == "Faltam 2 horas.")
    }

    @Test("Under a minute, and at or past kick-off")
    func edges() {
        #expect(remaining(30) == "Falta menos de um minuto.")
        #expect(remaining(0) == "Está na hora do jogo.")
        #expect(remaining(-120) == "Está na hora do jogo.")
    }
}
