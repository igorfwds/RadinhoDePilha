import AVFoundation
import Foundation

/// Speaks narration through the platform synthesiser.
///
/// An `actor` because it owns mutable state, the queue and what is currently being spoken, that
/// is touched from the polling loop, from the interface, and from the synthesiser's own callbacks.
/// Serialising that state is exactly what an actor is for, and it is the mechanism described in
/// Section 3.7.4 of the theoretical background.
///
/// Priority handling lives here rather than in the synthesiser because `AVSpeechSynthesizer` keeps
/// its own opaque queue that cannot be inspected or reordered. Feeding it one utterance at a time
/// and holding the queue locally is what allows a goal to jump ahead of a substitution.
///
/// Deduplication is deliberately absent: the caller decides what is new. Replaying a bookmarked
/// moment must be able to speak something already spoken.
actor AVSpeechService: SpeechService {
    private let policy: SpeechInterruptionPolicy
    private let languageCode: String

    /// Created on first use rather than in `init`.
    ///
    /// The synthesiser wrapper is isolated to the main actor, and an actor's initialiser runs
    /// nonisolated, so it cannot be built here. Deferring also means no audio machinery is spun up
    /// for a service that ends up never speaking.
    private var box: SpeechSynthesizerBox?

    private var queue = SpeechQueue()

    /// What is being spoken right now, so a settings change can restart it.
    ///
    /// Stays set until the sentence genuinely finishes. Clearing it while the restart is in flight
    /// opened a window where a second change found nothing to restart.
    private var speaking: PendingUtterance?

    /// Whether the sentence in progress was cut off to be spoken again at a new setting.
    ///
    /// Distinguishes "stopped because the listener changed something" from "finished speaking",
    /// which look identical from the synthesiser's callback.
    private var restartRequested = false

    private var currentPriority: NarrationPriority?
    private var isPumping = false
    private var rate: SpeechRate

    /// Voice chosen by the listener, or `nil` for automatic selection.
    private var voiceIdentifier: String?

    init(
        rate: SpeechRate = .normal,
        policy: SpeechInterruptionPolicy = .above(.high),
        languageCode: String = "pt-BR"
    ) {
        self.rate = rate
        self.policy = policy
        self.languageCode = languageCode
    }

    private func synthesizer() async -> SpeechSynthesizerBox {
        if let box { return box }

        let created = await MainActor.run { SpeechSynthesizerBox(languageCode: languageCode) }
        box = created

        return created
    }

    // MARK: - SpeechService

    func speak(_ narration: Narration) async {
        await enqueue(
            PendingUtterance(
                id: narration.id,
                text: narration.text,
                priority: narration.priority
            )
        )
    }

    func speakNow(_ narration: Narration) async {
        await speakNow(
            PendingUtterance(
                id: narration.id,
                text: narration.text,
                priority: narration.priority,
                isOnDemand: true
            )
        )
    }

    func speak(_ text: String, priority: NarrationPriority = .normal) async {
        await enqueue(PendingUtterance(id: UUID().uuidString, text: text, priority: priority))
    }

    func speakNow(_ text: String, priority: NarrationPriority = .normal) async {
        await speakNow(
            PendingUtterance(
                id: UUID().uuidString,
                text: text,
                priority: priority,
                isOnDemand: true
            )
        )
    }

    /// Cuts off what is being said and speaks this instead.
    private func speakNow(_ utterance: PendingUtterance) async {
        // Replaces any earlier request rather than joining a queue behind it: tapping twice means
        // the first answer is no longer wanted.
        queue.removeOnDemand()

        // The match kept going while the listener was asking for something else. Returning to a
        // backlog of stale commentary is not what "live" means, so only the newest event survives.
        queue.keepOnlyLatestEvent()

        queue.enqueue(utterance)

        // Unconditional, which is the difference from `speak`. The interruption policy governs
        // what the *match* may interrupt; a direct request from the listener is not subject to it.
        currentPriority = nil
        await synthesizer().stop()

        startPumpIfNeeded()
    }

    func stopAll() async {
        queue.removeAll()
        currentPriority = nil
        speaking = nil
        restartRequested = false
        await synthesizer().stop()
    }

    func setVoice(identifier: String?) async {
        guard identifier != voiceIdentifier else { return }

        voiceIdentifier = identifier
        await restartCurrentUtterance()
    }

    func setRate(_ rate: SpeechRate) async {
        guard rate != self.rate else { return }

        self.rate = rate
        await restartCurrentUtterance()
    }

    /// Restarts the sentence in progress so a settings change is heard immediately.
    ///
    /// `AVSpeechUtterance` fixes its rate and voice when it is created, so there is no way to alter
    /// speech already under way. Restarting the sentence is what makes the control feel connected
    /// to the sound: waiting for the next event would leave the listener wondering whether the
    /// change registered, and during a quiet stretch of a match that wait can be minutes.
    ///
    /// The sentence goes back to the front of the queue rather than being dropped, so nothing is
    /// lost, it is simply heard again at the new setting.
    private func restartCurrentUtterance() async {
        guard let speaking else { return }

        // Already queued for a restart. The pump has not resumed yet, and when it does it will use
        // whatever the settings say at that moment, so a second change needs no second requeue,
        // and adding one would speak the sentence twice.
        guard !restartRequested else { return }

        restartRequested = true
        queue.prepend(speaking)
        currentPriority = nil

        await synthesizer().stop()
        startPumpIfNeeded()
    }

    /// Prepares the audio session. Call once, before the first utterance.
    func activate() async {
        await synthesizer().activateAudioSession()
    }

    // MARK: - Queueing

    private func enqueue(_ utterance: PendingUtterance) async {
        queue.enqueue(utterance)

        // Deliberately does not interrupt. Match events are narrated in the order they happened,
        // and cutting off "cartão amarelo para Wanderson" to start the goal that came after it
        // would leave the listener with half a sentence and a broken timeline. Interruption is
        // reserved for what the listener asks for; see `speakNow`.
        //
        // `policy` still describes the rule and is exercised by its own tests, because the
        // dissertation's OE1 commits to a priority queue and the reasoning is part of the result.
        startPumpIfNeeded()
    }

    private func startPumpIfNeeded() {
        guard !isPumping else { return }
        isPumping = true

        Task { [weak self] in
            await self?.pump()
        }
    }

    /// Speaks queued utterances, highest priority first, until the queue empties.
    private func pump() async {
        while let next = queue.takeNext() {
            currentPriority = next.priority
            speaking = next

            await synthesizer().speak(
                next.text,
                rateMultiplier: rate.multiplier,
                voiceIdentifier: voiceIdentifier
            )

            currentPriority = nil

            if restartRequested {
                // Cut off on purpose: the sentence is already back at the front of the queue and
                // `speaking` stays set, so the next change to arrive can cut it off again. This is
                // what makes the setting respond to every touch rather than only the first.
                restartRequested = false
            } else {
                speaking = nil
            }
        }

        isPumping = false
    }

}

/// Holds the synthesiser and turns its delegate callbacks into an awaitable call.
///
/// Isolated to the main actor because `AVSpeechSynthesizer` is not `Sendable` and its delegate
/// callbacks arrive on an unspecified thread. Pinning ownership to one actor and hopping onto it
/// from the callbacks is what makes the whole thing safe under Swift 6 checking.
@MainActor
private final class SpeechSynthesizerBox: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let languageCode: String
    private var continuation: CheckedContinuation<Void, Never>?
    private var didActivateSession = false

    /// The utterance currently awaited, identified so that late callbacks can be told apart.
    ///
    /// Without this, restarting a sentence broke after the first time. Stopping a sentence schedules
    /// its `didCancel`, which arrives *after* the replacement sentence has already started, and,
    /// having no way to know which sentence it referred to, it resumed the new one's continuation
    /// and made the app believe that sentence had finished. The result was that only the first
    /// change of speed took effect; the second appeared to skip ahead.
    private var awaitedUtterance: AVSpeechUtterance?

    /// Guards against a sentence that is handed to the synthesiser and never starts.
    ///
    /// The synthesiser can drop a `speak` silently, no error, no callback, and the pump would then
    /// wait forever on a continuation nobody resumes, killing narration for the rest of the match.
    /// Cancelled as soon as speech actually begins, so a long sentence is never cut short.
    private var startWatchdog: Task<Void, Never>?

    init(languageCode: String) {
        self.languageCode = languageCode
        super.init()
        synthesizer.delegate = self
    }

    /// Configures the audio session for spoken content.
    ///
    /// `.duckOthers` lowers other audio instead of stopping it, which matters because a listener
    /// may well be following the radio broadcast at the same time. `.spokenAudio` tells the system
    /// this is speech rather than music, so it routes and interacts with other audio accordingly.
    func activateAudioSession() {
        guard !didActivateSession else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            didActivateSession = true
        } catch {
            // Speech still works with the default session in most cases, so a failure here
            // degrades quality rather than function. Worth surfacing in logs once there is a
            // logging facility; not worth failing the narration over.
        }
    }

    func speak(_ text: String, rateMultiplier: Float, voiceIdentifier: String? = nil) async {
        // Defence in depth. `stop` already waits for the synthesiser to settle, but a `speak`
        // handed over while it is still winding down is discarded silently, and the cost of that
        // is the voice dying for the rest of the match. Checking here means no caller can cause it.
        await waitUntilIdle()

        await withCheckedContinuation { continuation in
            // A pending continuation means a previous utterance never reported completion.
            // Resuming it here keeps the queue moving instead of deadlocking the pump.
            resumePending()
            self.continuation = continuation

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice(identifier: voiceIdentifier, language: languageCode)
            utterance.rate = Self.clampedRate(multiplier: rateMultiplier)
            utterance.postUtteranceDelay = 0.15

            awaitedUtterance = utterance
            synthesizer.speak(utterance)
            startWatchdog(for: utterance)
        }
    }

    /// Releases the waiting caller if speech never begins.
    private func startWatchdog(for utterance: AVSpeechUtterance) {
        startWatchdog?.cancel()

        startWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))

            guard !Task.isCancelled,
                  let self,
                  let awaited = self.awaitedUtterance,
                  ObjectIdentifier(awaited) == ObjectIdentifier(utterance),
                  !self.synthesizer.isSpeaking
            else { return }

            // Handed over, never started, still nothing playing: treat it as lost and let the queue
            // move on rather than stalling on it.
            self.awaitedUtterance = nil
            self.resumePending()
        }
    }

    /// Stops what is being spoken and waits until the synthesiser is genuinely idle.
    ///
    /// The wait is the important part. `AVSpeechSynthesizer` ignores `speak` while it is still
    /// winding down from `stopSpeaking`, and does so **silently**, no error, no callback. The next
    /// sentence then never starts and never reports completion, so the pump waits on a continuation
    /// that will never be resumed and narration dies for good. That is what happened when the speed
    /// was changed several times in quick succession.
    ///
    /// Bounded rather than open-ended: if the synthesiser never settles, giving up and carrying on
    /// is better than hanging.
    func stop() async {
        // Disowned before stopping, so the `didCancel` this triggers is recognised as belonging to
        // a sentence nobody is waiting on any more.
        awaitedUtterance = nil

        synthesizer.stopSpeaking(at: .immediate)

        // Waits *before* releasing the caller, and the order is the whole point. Releasing first
        // let the pump call `speak` while the synthesiser was still winding down, and a `speak`
        // issued in that window is discarded without a word. That is what killed the voice after
        // several changes in a row.
        await waitUntilIdle()

        // `didCancel` is expected to have fired by now, but resuming defensively avoids a stall if
        // it did not.
        resumePending()
    }

    /// Roughly 200 ms of grace for the synthesiser to stop, in 10 ms steps.
    private static let settleAttempts = 20

    /// Waits for the synthesiser to stop reporting speech, up to a bounded number of attempts.
    ///
    /// Bounded rather than open ended: if it never settles, carrying on is better than hanging.
    private func waitUntilIdle() async {
        var attempts = 0

        while synthesizer.isSpeaking, attempts < Self.settleAttempts {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        // Speech is genuinely under way, so the watchdog has nothing left to guard.
        Task { @MainActor [weak self] in self?.startWatchdog?.cancel() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        // Only the identity crosses over: `AVSpeechUtterance` is not `Sendable`, and the object
        // itself must not leave the thread the callback arrived on.
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(identity) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(identity) }
    }

    /// Resumes the waiting caller, but only for the sentence it is actually waiting on.
    ///
    /// Callbacks hop onto this actor, so they can arrive after the next sentence has started.
    /// Comparing identity is what keeps a stale one from cutting the new sentence short.
    private func finished(_ identity: ObjectIdentifier) {
        guard let awaitedUtterance,
              identity == ObjectIdentifier(awaitedUtterance)
        else { return }

        self.awaitedUtterance = nil
        startWatchdog?.cancel()
        resumePending()
    }

    // MARK: - Helpers

    private func resumePending() {
        continuation?.resume()
        continuation = nil
    }

    /// Picks the best installed voice for the language.
    ///
    /// Quality is not cosmetic here: this voice speaks continuously for ninety minutes, and the
    /// listener depends on it entirely. Prefers premium, then enhanced, then whatever exists.
    /// Resolves the voice to use: the chosen one when still installed, otherwise the best
    /// available.
    ///
    /// Falling back matters because a chosen voice can disappear, the listener may delete the
    /// download in system settings, and a stored identifier would then resolve to nothing and
    /// leave the app silent.
    private static func voice(identifier: String?, language: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }

        return bestVoice(for: language)
    }

    private static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == languageCode }

        if let premium = candidates.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = candidates.first(where: { $0.quality == .enhanced }) { return enhanced }

        return candidates.first ?? AVSpeechSynthesisVoice(language: languageCode)
    }

    /// Applies the multiplier to the platform default and keeps the result within valid bounds.
    ///
    /// The bounds are global constants rather than members of `AVSpeechUtterance`, and the property
    /// pins out-of-range values silently, clamping here makes the ceiling explicit instead of
    /// letting a "very fast" setting quietly behave like "fast".
    private static func clampedRate(multiplier: Float) -> Float {
        let desired = AVSpeechUtteranceDefaultSpeechRate * multiplier

        return min(
            max(desired, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
    }
}
