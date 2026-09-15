import Foundation

/// Anything able to speak narration aloud.
///
/// Declared as a protocol so that view models can be tested without a synthesiser running: the
/// real one depends on audio hardware, takes real time to finish, and cannot be inspected. A test
/// double records what it was asked to say instead.
nonisolated protocol SpeechService: Sendable {
    /// Queues narration to be spoken.
    ///
    /// Higher-priority narration may interrupt speech already in progress; see
    /// ``SpeechInterruptionPolicy``.
    func speak(_ narration: Narration) async

    /// Speaks narration the listener asked for, cutting off whatever is being said.
    ///
    /// Distinct from ``speak(_:)`` because a tap is a question, and answering it after the current
    /// sentence finishes reads as the app ignoring the tap. Any earlier on-demand request is
    /// dropped — asking for a second moment means the first is no longer wanted — while queued
    /// match events survive, since losing a goal to a replay would lose it permanently.
    func speakNow(_ narration: Narration) async

    /// Speaks arbitrary text, for interface feedback that is not a match event.
    func speak(_ text: String, priority: NarrationPriority) async

    /// Stops what is being spoken and clears anything queued.
    func stopAll() async

    /// Rate at which speech is produced, as a fraction of the platform's normal rate.
    func setRate(_ rate: SpeechRate) async
}

/// Speech rate, exposed as named steps rather than raw float values.
///
/// Named steps exist because the raw scale used by the synthesiser is not meaningful to a user,
/// and because the settings screen has to describe the choice out loud. "Rápida" can be spoken;
/// "0.55" cannot.
nonisolated enum SpeechRate: String, CaseIterable, Sendable {
    case slow
    case normal
    case fast
    case veryFast

    /// Label for the settings screen, in Brazilian Portuguese.
    var displayName: String {
        switch self {
        case .slow: "Lenta"
        case .normal: "Normal"
        case .fast: "Rápida"
        case .veryFast: "Muito rápida"
        }
    }

    /// Multiplier applied to the platform's default utterance rate.
    ///
    /// Expressed relative to the default rather than as an absolute value so the setting keeps
    /// meaning if Apple changes the baseline, and so it composes with the rate the user may
    /// already have configured system-wide for VoiceOver.
    var multiplier: Float {
        switch self {
        case .slow: 0.8
        case .normal: 1.0
        case .fast: 1.25
        case .veryFast: 1.5
        }
    }
}

/// When newly arriving narration may cut off speech already under way.
nonisolated enum SpeechInterruptionPolicy: Sendable {
    /// Nothing interrupts; everything waits its turn.
    case never

    /// Narration strictly above the given priority interrupts.
    case above(NarrationPriority)

    func allowsInterrupting(current: NarrationPriority, with incoming: NarrationPriority) -> Bool {
        switch self {
        case .never:
            false
        case let .above(threshold):
            incoming > current && incoming > threshold
        }
    }
}
