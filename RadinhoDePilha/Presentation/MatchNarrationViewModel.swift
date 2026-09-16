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
/// carry the score inside them, so the app announced 2×1 and then announced 0×1, for someone
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

    // MARK: - Dependencies

    private let provider: MatchDataProvider
    private let speech: any SpeechService

    /// Not `let`, because the listener can change persona mid-match.
    private var engine: any NarrationEngine

    /// Gap between polls.
    ///
    /// Injected because the right value differs by provider: the simulated provider needs a short
    /// gap for the match to be heard moving, while API-Football bills per request.
    ///
    /// The default follows the vendor's own guidance, one call per minute for fixtures in
    /// progress, rather than a guess. Their data refreshes every fifteen seconds, so polling
    /// faster buys little and risks the firewall: exceeding the per-minute rate can get an account
    /// blocked without notice.
    private let pollInterval: Duration

    /// Failures tolerated before the loop gives up.
    private let failureLimit = 3

    init(
        provider: MatchDataProvider,
        engine: any NarrationEngine = TemplateNarrationEngine(),
        speech: any SpeechService,
        pollInterval: Duration = .seconds(60)
    ) {
        self.provider = provider
        self.engine = engine
        self.speech = speech
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

        // Everything already on screen counts as heard. This is the whole fix: the backlog is
        // acknowledged silently instead of being recited out of order.
        spokenIDs.formUnion(narrations.map(\.id))

        guard match.isLive else {
            // Cuts off whatever is queued. Hearing "esta partida já terminou" only after the
            // remaining commentary drains makes the button look broken, the answer has to
            // arrive while the listener still connects it to the tap.
            await announceNotLive(match)
            return
        }

        isNarrating = true

        // Confirming out loud is not decoration. Play that produces silence until the next event
        // is indistinguishable from a frozen app for someone who cannot see the button change.
        await speech.speakNow("Narração ao vivo.", priority: .normal)

        // Then the latest moment, so resuming lands the listener in the present instead of in
        // silence. Reported from use: pausing and resuming with no new event in between left the
        // narrator mute, which reads as broken rather than as "nothing has happened yet".
        //
        // Only the most recent one, reciting the backlog is the defect this whole design avoids.
        if let latest = narrations.last {
            await speech.speak(latest)
        }

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

        // Chronological, one after another. Events arrive from the mapper in the order they
        // happened, and that order is preserved all the way to the synthesiser: the sentences
        // carry the running score inside them, so speaking a later goal before an earlier booking
        // makes the score appear to move backwards.
        for event in newEvents {
            guard let narration = engine.narrate(event, in: fresh) else { continue }

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
        case .abandoned:
            "Esta partida foi abandonada e não será concluída."
        case .awarded:
            "Esta partida foi decidida fora de campo, sem ser jogada até o fim."
        case .postponed:
            "Esta partida foi adiada."
        case .cancelled:
            "Esta partida foi cancelada."
        default:
            "A partida não está em andamento."
        }

        errorMessage = nil
        await speech.speakNow(message, priority: .high)
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
    /// sentence, or through every sentence tapped before it, makes the list feel unresponsive,
    /// and on a screen the listener cannot see, an unanswered tap gives no sign that it landed.
    func replay(_ narration: Narration) async {
        await speech.speakNow(narration)
    }

    /// Whether a narration has already been spoken, for the interface to mark it.
    func wasSpoken(_ narration: Narration) -> Bool {
        spokenIDs.contains(narration.id)
    }

    // MARK: - Persona

    /// Switches the narrating persona and rewords what is on screen.
    ///
    /// Re-narrating the existing events is the point: a listener who changes persona expects the
    /// match they are reading to be phrased the new way, not only the events still to come.
    ///
    /// ``spokenIDs`` is left untouched. The events already happened and were already heard 
    /// rewording them is not a reason to say them again, and re-speaking a match on a settings
    /// change would be the same defect that made play recite the backlog.
    func setPersona(_ persona: NarratorPersona) {
        engine = TemplateNarrationEngine(persona: persona)

        guard let match else { return }
        narrations = match.events.compactMap { engine.narrate($0, in: match) }
    }
}
