import AVFoundation
import Foundation

/// Speaks narration through the platform synthesiser.
///
/// An `actor` because it owns mutable state — the queue and what is currently being spoken — that
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
        await synthesizer().stop()
    }

    func setVoice(identifier: String?) async {
        voiceIdentifier = identifier
    }

    func setRate(_ rate: SpeechRate) async {
        self.rate = rate
        // Applies from the next utterance onwards. Changing the rate mid-sentence would mean
        // cutting the sentence off and starting it again, which is worse than finishing it.
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
            await synthesizer().speak(
                next.text,
                rateMultiplier: rate.multiplier,
                voiceIdentifier: voiceIdentifier
            )
            currentPriority = nil
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
        await withCheckedContinuation { continuation in
            // A pending continuation means a previous utterance never reported completion.
            // Resuming it here keeps the queue moving instead of deadlocking the pump.
            resumePending()
            self.continuation = continuation

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice(identifier: voiceIdentifier, language: languageCode)
            utterance.rate = Self.clampedRate(multiplier: rateMultiplier)
            utterance.postUtteranceDelay = 0.15

            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // `didCancel` is expected to fire, but resuming defensively avoids a stall if it does not.
        resumePending()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.resumePending() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.resumePending() }
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
    /// Falling back matters because a chosen voice can disappear — the listener may delete the
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
    /// pins out-of-range values silently — clamping here makes the ceiling explicit instead of
    /// letting a "very fast" setting quietly behave like "fast".
    private static func clampedRate(multiplier: Float) -> Float {
        let desired = AVSpeechUtteranceDefaultSpeechRate * multiplier

        return min(
            max(desired, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
    }
}
