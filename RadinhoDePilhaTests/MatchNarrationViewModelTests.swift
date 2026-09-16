import Foundation
import Testing
@testable import RadinhoDePilha

/// Records what it was asked to say, instead of saying it.
///
/// An `actor` so it satisfies the `Sendable` contract of ``SpeechService`` without locks.
actor SpeechServiceSpy: SpeechService {
    private(set) var spoken: [Narration] = []
    private(set) var spokenText: [String] = []
    private(set) var stopCount = 0
    private(set) var appliedRates: [SpeechRate] = []
    private(set) var appliedVoices: [String?] = []
    private(set) var activateCount = 0

    /// Narration requested through ``speakNow(_:)``, which must interrupt rather than queue.
    private(set) var interrupting: [Narration] = []

    /// Interface feedback that must interrupt too, for the same reason.
    private(set) var interruptingText: [String] = []

    func speak(_ narration: Narration) async {
        spoken.append(narration)
    }

    func speakNow(_ narration: Narration) async {
        interrupting.append(narration)
        spoken.append(narration)
    }

    func speak(_ text: String, priority: NarrationPriority) async {
        spokenText.append(text)
    }

    func speakNow(_ text: String, priority: NarrationPriority) async {
        interruptingText.append(text)
        spokenText.append(text)
    }

    func stopAll() async {
        stopCount += 1
    }

    func setRate(_ rate: SpeechRate) async {
        appliedRates.append(rate)
    }

    func setVoice(identifier: String?) async {
        appliedVoices.append(identifier)
    }

    func activate() async {
        activateCount += 1
    }
}

/// Always fails, to exercise error handling.
nonisolated struct FailingMatchDataProvider: MatchDataProvider {
    let error: MatchDataError

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        throw error
    }

    func match(withID id: String) async throws -> Match {
        throw error
    }
}

/// Hands out a prepared sequence of match states, one per call.
///
/// Lets the live loop be tested without a clock: successive polls see the match advance exactly
/// as scripted, and the last state repeats once the script runs out.
actor ScriptedMatchDataProvider: MatchDataProvider {
    private let states: [Match]
    private var callCount = 0

    init(states: [Match]) {
        self.states = states
    }

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        states.isEmpty ? [] : [states[min(callCount, states.count - 1)]]
    }

    func match(withID id: String) async throws -> Match {
        guard !states.isEmpty else { throw MatchDataError.matchNotFound(id: id) }

        let state = states[min(callCount, states.count - 1)]
        callCount += 1

        return state
    }
}

/// Waits for a condition to hold, rather than sleeping a fixed amount.
///
/// The live loop runs on its own task, so tests have to wait for it. Polling a condition keeps
/// them from failing on a slow machine and from wasting time on a fast one.
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async -> Bool
) async {
    let deadline = ContinuousClock.now + timeout

    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("Match narration view model")
@MainActor
struct MatchNarrationViewModelTests {
    private func makeViewModel(
        provider: MatchDataProvider = InMemoryMatchDataProvider.sample(),
        speech: SpeechServiceSpy = SpeechServiceSpy(),
        pollInterval: Duration = .seconds(60)
    ) -> (MatchNarrationViewModel, SpeechServiceSpy) {
        (
            MatchNarrationViewModel(provider: provider, speech: speech, pollInterval: pollInterval),
            speech
        )
    }

    /// Successive states of the sample match, one per requested offset.
    ///
    /// Derived from ``SimulatedLiveMatchProvider`` at fixed instants rather than from the wall
    /// clock, so the states are the same on every run. Starting at minute 60 with one second per
    /// match minute puts the substitution at 61 one second in and the penalty at 66 six in.
    private func liveStates(atOffsets offsets: [TimeInterval]) -> [Match] {
        let origin = Date(timeIntervalSince1970: 0)
        let simulator = SimulatedLiveMatchProvider(
            base: SampleMatches.liveComeback,
            startMinute: 60,
            secondsPerMatchMinute: 1,
            startedAt: origin
        )

        return offsets.map { simulator.state(at: origin.addingTimeInterval($0)) }
    }

    // MARK: - Loading

    @Test("Loading a match produces narration in chronological order")
    func loadProducesChronologicalNarration() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        #expect(viewModel.match != nil)
        #expect(!viewModel.narrations.isEmpty)

        let minutes = viewModel.narrations.map(\.minute)
        #expect(minutes == minutes.sorted())
    }

    @Test("Loading clears the loading flag when finished")
    func loadClearsLoadingFlag() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        #expect(!viewModel.isLoading)
    }

    @Test("An unknown match surfaces a message the user can understand")
    func unknownMatchSurfacesMessage() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load(matchID: "nao-existe")

        #expect(viewModel.match == nil)
        #expect(viewModel.errorMessage != nil)
        // The message must be the vendor-neutral, user-facing one, not a decoding detail.
        #expect(viewModel.errorMessage == MatchDataError.matchNotFound(id: "x").userFacingMessage)
    }

    @Test("An exhausted quota surfaces its own message")
    func quotaExceededSurfacesMessage() async {
        let provider = FailingMatchDataProvider(error: .quotaExceeded)
        let (viewModel, _) = makeViewModel(provider: provider)

        await viewModel.load(matchID: "qualquer")

        #expect(viewModel.errorMessage == MatchDataError.quotaExceeded.userFacingMessage)
    }

    // MARK: - Narration

    @Test("Pressing play does not recite what already happened")
    func startingDoesNotReciteBacklog() async {
        // The defect this guards against was heard before it was found: the backlog was queued
        // by priority, so the app announced the closing score and then an earlier one.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()

        #expect(await spy.spoken.isEmpty)
    }

    @Test("Pressing play says out loud that narration is live")
    func startingConfirmsAloud() async {
        // Silence after pressing play is indistinguishable from a frozen app for a listener who
        // cannot see the button change.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()

        #expect(await !spy.spokenText.isEmpty)
    }

    @Test("Events arriving together are narrated in the order they happened")
    func simultaneousEventsStayChronological() async {
        // Priority used to reorder these, so the penalty at 66 was announced before the
        // substitution at 61. Reported from use: the narration has to follow the timeline,
        // one moment after another, because the sentences carry the running score.
        let states = liveStates(atOffsets: [0, 7])
        let provider = ScriptedMatchDataProvider(states: states)
        let (viewModel, spy) = makeViewModel(provider: provider, pollInterval: .milliseconds(10))

        await viewModel.load(matchID: SampleMatches.liveComeback.id)
        await viewModel.startNarrating()

        await waitUntil { await spy.spoken.count >= 2 }
        await viewModel.stopNarrating()

        let minutes = await spy.spoken.map(\.minute)
        #expect(minutes == minutes.sorted())
        #expect(minutes.first == 61)
    }

    @Test("Events arriving while live are narrated as they arrive")
    func liveEventsAreNarrated() async {
        let states = liveStates(atOffsets: [0, 2, 7])
        let provider = ScriptedMatchDataProvider(states: states)
        let (viewModel, spy) = makeViewModel(provider: provider, pollInterval: .milliseconds(10))

        await viewModel.load(matchID: SampleMatches.liveComeback.id)
        await viewModel.startNarrating()

        await waitUntil { await spy.spoken.count >= 2 }
        await viewModel.stopNarrating()

        let minutes = await spy.spoken.map(\.minute)
        // One state adds the substitution at 61, the next the penalty at 66. Arriving in
        // separate cycles, they are heard in the order they happened.
        #expect(minutes == [61, 66])
    }

    @Test("A match that is over is announced instead of narrated")
    func finishedMatchIsAnnounced() async {
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.finishedWithRedCard.id)

        await viewModel.startNarrating()

        #expect(!viewModel.isNarrating)
        #expect(await spy.spoken.isEmpty)
        #expect(await spy.spokenText.contains { $0.contains("terminou") })
    }

    @Test("Answering a tap interrupts the queue instead of waiting for it to drain")
    func tapAnswersInterrupt() async {
        // Reported from use: with commentary still queued, pressing play on a finished match
        // only said "esta partida já terminou" once the queue ran out — long enough after the
        // tap that the two no longer seemed related.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.finishedWithRedCard.id)

        await viewModel.startNarrating()

        #expect(await spy.interruptingText.contains { $0.contains("terminou") })
    }

    @Test("Starting live narration confirms through an interrupting utterance")
    func liveConfirmationInterrupts() async {
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()
        await viewModel.stopNarrating()

        #expect(await spy.interruptingText.contains { $0.contains("ao vivo") })
    }

    // MARK: - Summary

    @Test("The summary is spoken only when asked for")
    func summaryIsOnDemand() async {
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()
        #expect(await spy.spoken.isEmpty)

        await viewModel.speakSummary()

        let spoken = await spy.spoken
        #expect(spoken.count == 1)
        // States the score, which is the question someone tuning in is asking.
        #expect(spoken.first?.text.contains("Náutico 2") == true)
    }

    @Test("Narrating twice does not repeat what was already spoken")
    func narratingTwiceDoesNotRepeat() async {
        // Guards against the app replaying the whole match on every polling cycle.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()
        let afterFirst = await spy.spoken.count

        await viewModel.startNarrating()
        let afterSecond = await spy.spoken.count

        #expect(afterFirst == afterSecond)
    }

    @Test("Stopping clears the narrating flag and stops the speech service")
    func stoppingStopsSpeech() async {
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.startNarrating()
        await viewModel.stopNarrating()

        #expect(!viewModel.isNarrating)
        #expect(await spy.stopCount == 1)
    }

    // MARK: - Replay

    @Test("Replay speaks a moment again even though it was already spoken")
    func replayRepeatsSpokenMoment() async throws {
        // The whole point of the replay feature: hearing again what you already heard.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)
        await viewModel.startNarrating()

        let target = try #require(viewModel.narrations.first)
        let before = await spy.spoken.count

        await viewModel.replay(target)

        #expect(await spy.spoken.count == before + 1)
        #expect(await spy.spoken.last?.id == target.id)
    }

    @Test("Replay interrupts instead of waiting its turn")
    func replayInterrupts() async throws {
        // Tapping a moment and hearing the previous one finish first reads as the tap being
        // ignored, which on a screen the listener cannot see leaves no clue that it landed.
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        let first = try #require(viewModel.narrations.first)
        let second = try #require(viewModel.narrations.last)

        await viewModel.replay(first)
        await viewModel.replay(second)

        let interrupting = await spy.interrupting
        #expect(interrupting.count == 2)
        #expect(interrupting.map(\.id) == [first.id, second.id])
    }

    @Test("The summary interrupts too, since it was asked for")
    func summaryInterrupts() async {
        let (viewModel, spy) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        await viewModel.speakSummary()

        #expect(await spy.interrupting.count == 1)
    }

    @Test("Spoken moments are marked as such for the interface")
    func spokenMomentsAreMarked() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.load(matchID: SampleMatches.liveComeback.id)

        let target = try #require(viewModel.narrations.first)
        #expect(!viewModel.wasSpoken(target))

        await viewModel.startNarrating()

        #expect(viewModel.wasSpoken(target))
    }

    // MARK: - Rate

    @Test("Changing the rate forwards it to the speech service")
    func changingRateForwardsIt() async {
        let (viewModel, spy) = makeViewModel()

        viewModel.rate = .fast
        // The change is forwarded from a detached task, so yield until it lands.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await spy.appliedRates.contains(.fast))
    }

    @Test("Setting the same rate again does not re-apply it")
    func settingSameRateIsIgnored() async {
        let (viewModel, spy) = makeViewModel()

        viewModel.rate = .normal
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await spy.appliedRates.isEmpty)
    }
}
