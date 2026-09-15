import Foundation
import Observation

/// Drives the narration screen.
///
/// Owns the match being followed, the narration produced from it, and what has already been
/// spoken. Isolated to the main actor because it feeds SwiftUI directly; the work it delegates to
/// (data access, speech) lives off the main actor in its own types.
///
/// Dependencies arrive by injection so the screen can be driven by in-memory data during
/// development and by a recording double in tests, without a synthesiser or a network.
///
/// ## Why pressing play does not recite the match
///
/// It used to. Everything known was queued at once, and because the speech queue orders by
/// priority, the listener heard every goal first and "Começa o jogo" last. Worse, the sentences
/// carry the score inside them, so the app announced 2×1 and then announced 0×1 — for someone
/// who cannot see the screen, plain misinformation with no way to catch it.
///
/// Play now behaves like switching a radio on mid-match: what already happened is marked as heard
/// without being spoken, and narration follows the match from that instant. A listener who wants
/// the background asks for it, through ``speakSummary()``.
///
/// Priority still governs speech, but only where it was meant to: among events that arrive within
/// the same polling cycle, so a goal is not held up behind a substitution.
@MainActor
@Observable
final class MatchNarrationViewModel {
    // MARK: - State

    private(set) var match: Match?

    /// Narration for every known event, oldest first.
    ///
    /// Chronological rather than by priority: this list is what the screen shows, and a listener
    /// scrolling back through the match expects it in the order things happened. Priority governs
    /// the order of *speech*, which is the speech queue's business.
    private(set) var narrations: [Narration] = []

    private(set) var isNarrating = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Identifiers already spoken, or deliberately skipped as backlog.
    private var spokenIDs: Set<String> = []

    /// Consecutive failed polls, to tell a blip apart from a real outage.
    private var consecutiveFailures = 0

    /// The polling loop, while one is running.
    ///
    /// Not cancelled from `deinit`, which is nonisolated and cannot touch main-actor state. The
    /// loop captures `self` weakly and returns on the first iteration after deallocation, so it
    /// ends on its own. Screens should still call ``suspend()`` when they disappear, to stop
    /// polling immediately rather than one interval later.
    private var liveTask: Task<Void, Never>?

    var rate: SpeechRate {
        didSet {
            guard rate != oldValue else { return }
            Task { await speech.setRate(rate) }
        }
    }

    // MARK: - Dependencies

    private let provider: MatchDataProvider
    private let engine: any NarrationEngine
    private let speech: any SpeechService

    /// Gap between polls.
    ///
    /// Injected because the right value differs by provider: the API-Football plan bills per
    /// request and tolerates thirty seconds, while the simulated provider needs a much shorter
    /// gap for the match to be heard moving at all.
    private let pollInterval: Duration

    /// Failures tolerated before the loop gives up.
    private let failureLimit = 3

    init(
        provider: MatchDataProvider,
        engine: any NarrationEngine = TemplateNarrationEngine(),
        speech: any SpeechService,
        rate: SpeechRate = .normal,
        pollInterval: Duration = .seconds(30)
    ) {
        self.provider = provider
        self.engine = engine
        self.speech = speech
        self.rate = rate
        self.pollInterval = pollInterval
    }

    // MARK: - Loading

    func load(matchID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await provider.match(withID: matchID)
            apply(loaded)
        } catch let error as MatchDataError {
            errorMessage = error.userFacingMessage
        } catch {
            errorMessage = "Não foi possível carregar a partida."
        }

        isLoading = false
    }

    /// Stores a freshly fetched match and rebuilds the narration list from it.
    ///
    /// Rebuilding wholesale rather than appending is deliberate: providers restate the full event
    /// list on every call, and an event's wording can legitimately change once later events are
    /// known. Identity lives in the event id, so nothing already spoken is spoken twice.
    private func apply(_ loaded: Match) {
        match = loaded
        // Events arrive chronologically, so mapping preserves that order. No sorting here:
        // priority ordering belongs to speech, not to the list on screen.
        narrations = loaded.events.compactMap { engine.narrate($0, in: loaded) }
    }

    // MARK: - Live narration

    /// Starts following the match from this moment on.
    func startNarrating() async {
        guard !isNarrating else { return }
        guard let match else { return }

        isNarrating = true

        // Everything already on screen counts as heard. This is the whole fix: the backlog is
        // acknowledged silently instead of being recited out of order.
        spokenIDs.formUnion(narrations.map(\.id))

        guard match.isLive else {
            await announceNotLive(match)
            isNarrating = false
            return
        }

        // Confirming out loud is not decoration. Play that produces silence until the next event
        // is indistinguishable from a frozen app for someone who cannot see the button change.
        await speech.speak("Narração ao vivo.", priority: .normal)

        startLiveLoop(matchID: match.id)
    }

    func stopNarrating() async {
        isNarrating = false
        liveTask?.cancel()
        liveTask = nil
        await speech.stopAll()
    }

    /// Stops the loop without speaking, for when the screen goes away.
    func suspend() {
        isNarrating = false
        liveTask?.cancel()
        liveTask = nil
    }

    private func startLiveLoop(matchID: String) {
        liveTask?.cancel()

        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                do {
                    try await Task.sleep(for: self.pollInterval)
                } catch {
                    return  // Cancelled while waiting.
                }

                guard !Task.isCancelled else { return }
                await self.poll(matchID: matchID)
            }
        }
    }

    /// One polling cycle: fetch, work out what is new, speak it.
    private func poll(matchID: String) async {
        do {
            let fresh = try await provider.match(withID: matchID)
            await recoverIfNeeded()
            await narrateNewEvents(in: fresh)
        } catch {
            await handlePollFailure()
        }
    }

    private func narrateNewEvents(in fresh: Match) async {
        let previous = match
        apply(fresh)

        let newEvents = fresh.events.filter { !spokenIDs.contains($0.id) }

        // Priority ordering is correct here and only here: these events arrived together, so
        // speaking a goal before a substitution reflects what matters, not a scrambled timeline.
        for narration in engine.narrate(newEvents, in: fresh) {
            spokenIDs.insert(narration.id)
            await speech.speak(narration)
        }

        if previous?.isLive == true, !fresh.isLive {
            await finishLiveNarration()
        }
    }

    /// Ends the session once the match is over.
    ///
    /// The final whistle is already narrated as an event; this only stops the loop and says that
    /// the app has stopped listening, so the silence that follows is explained rather than
    /// ambiguous.
    private func finishLiveNarration() async {
        suspend()
        await speech.speak("Fim da transmissão. Encerro a narração por aqui.", priority: .normal)
    }

    // MARK: - Exception states

    private func announceNotLive(_ match: Match) async {
        let message = switch match.status {
        case .scheduled:
            "A partida ainda não começou."
        case .finished:
            "Esta partida já terminou."
        case .postponed:
            "Esta partida foi adiada."
        case .cancelled:
            "Esta partida foi cancelada."
        default:
            "A partida não está em andamento."
        }

        errorMessage = nil
        await speech.speak(message, priority: .high)
    }

    private func handlePollFailure() async {
        consecutiveFailures += 1

        if consecutiveFailures == 1 {
            // Said once, on the first failure. Repeating it every cycle would talk over the match
            // the listener is trying to follow.
            await speech.speak(
                "Perdi o contato com os dados da partida. Continuo tentando.",
                priority: .high
            )
            return
        }

        guard consecutiveFailures >= failureLimit else { return }

        errorMessage = "Não foi possível continuar acompanhando a partida."
        suspend()
        await speech.speak(
            "Não consegui recuperar os dados da partida. Narração interrompida.",
            priority: .high
        )
    }

    private func recoverIfNeeded() async {
        guard consecutiveFailures > 0 else { return }

        consecutiveFailures = 0
        errorMessage = nil
        await speech.speak("Contato restabelecido.", priority: .normal)
    }

    // MARK: - On demand

    /// Speaks where the match stands, for someone who has just tuned in.
    ///
    /// Separate from play on purpose: catching up is a question the listener asks, not something
    /// imposed on them every time narration starts.
    func speakSummary() async {
        guard let match else { return }

        await speech.speakNow(engine.summary(of: match))
    }

    /// Speaks one narration again, on demand.
    ///
    /// Does not consult ``spokenIDs``: replay exists precisely to repeat something already heard,
    /// which is the behaviour described in the project's bookmark and replay feature.
    ///
    /// Interrupts whatever is being said. Tapping a moment and then waiting through the previous
    /// sentence — or through every sentence tapped before it — makes the list feel unresponsive,
    /// and on a screen the listener cannot see, an unanswered tap gives no sign that it landed.
    func replay(_ narration: Narration) async {
        await speech.speakNow(narration)
    }

    /// Whether a narration has already been spoken, for the interface to mark it.
    func wasSpoken(_ narration: Narration) -> Bool {
        spokenIDs.contains(narration.id)
    }
}
