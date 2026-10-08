import Foundation

/// One vibration within a pattern.
nonisolated struct HapticPulse: Hashable, Sendable {
    /// Seconds from the start of the pattern.
    let start: TimeInterval

    let duration: TimeInterval

    /// Strength, from 0 to 1.
    let intensity: Float

    /// Texture, from 0 (dull) to 1 (crisp).
    let sharpness: Float

    var end: TimeInterval { start + duration }
}

/// How much an event weighs, which the grammar expresses as strength.
nonisolated enum HapticSeverity: Hashable, Sendable, CaseIterable {
    case light
    case medium
    case strong

    var intensity: Float {
        switch self {
        case .light: 0.35
        case .medium: 0.6
        case .strong: 1.0
        }
    }
}

/// The vibration vocabulary of the app.
///
/// Three independent dimensions each carry one piece of information, so a pattern can be decoded
/// rather than memorised whole:
///
/// - **Rhythm** says what happened: one long pulse is a goal, two short ones a card, three quick
///   ones a substitution.
/// - **Strength** says how much it matters: strong for what changes the score or sends a player
///   off, medium for a booking, light for the rest.
/// - **Repetition** says for whom: the pattern plays once for the home side and twice for the away
///   side.
///
/// Kept as plain values with no dependency on the haptics framework, so the grammar itself can be
/// tested and described in the dissertation independently of the hardware that plays it.
nonisolated enum HapticGrammar {
    /// Silence between the two repetitions of an away-side pattern.
    static let repetitionGap: TimeInterval = 0.35

    static func severity(of kind: EventCueKind) -> HapticSeverity {
        switch kind {
        case .goal, .redCard:
            .strong
        case .yellowCard, .penalty:
            .medium
        case .substitution, .varReview, .whistle:
            .light
        }
    }

    /// The rhythm of one event kind, before repetition is applied.
    static func motif(for kind: EventCueKind) -> [HapticPulse] {
        let strength = severity(of: kind).intensity

        switch kind {
        case .goal:
            return [HapticPulse(start: 0, duration: 0.7, intensity: strength, sharpness: 0.5)]
        case .yellowCard:
            return [
                HapticPulse(start: 0, duration: 0.12, intensity: strength, sharpness: 0.8),
                HapticPulse(start: 0.25, duration: 0.12, intensity: strength, sharpness: 0.8)
            ]
        case .redCard:
            // The booking rhythm, then a long pulse: a card, and someone leaves.
            return [
                HapticPulse(start: 0, duration: 0.12, intensity: strength, sharpness: 0.8),
                HapticPulse(start: 0.25, duration: 0.12, intensity: strength, sharpness: 0.8),
                HapticPulse(start: 0.65, duration: 0.6, intensity: strength, sharpness: 0.3)
            ]
        case .substitution:
            return [
                HapticPulse(start: 0, duration: 0.07, intensity: strength, sharpness: 0.9),
                HapticPulse(start: 0.15, duration: 0.07, intensity: strength, sharpness: 0.9),
                HapticPulse(start: 0.30, duration: 0.07, intensity: strength, sharpness: 0.9)
            ]
        case .penalty:
            // Rises to the medium level instead of starting there, which reads as tension.
            return [
                HapticPulse(start: 0, duration: 0.15, intensity: strength * 0.4, sharpness: 0.4),
                HapticPulse(start: 0.15, duration: 0.15, intensity: strength * 0.6, sharpness: 0.5),
                HapticPulse(start: 0.30, duration: 0.15, intensity: strength * 0.8, sharpness: 0.6),
                HapticPulse(start: 0.45, duration: 0.2, intensity: strength, sharpness: 0.7)
            ]
        case .varReview:
            return [HapticPulse(start: 0, duration: 1.2, intensity: strength, sharpness: 0.2)]
        case .whistle:
            return [HapticPulse(start: 0, duration: 0.2, intensity: strength, sharpness: 0.6)]
        }
    }

    /// The full pattern for a cue: the motif once for the home side, twice for the away side.
    static func pulses(for cue: EventCue) -> [HapticPulse] {
        let single = motif(for: cue.kind)

        guard cue.side == .away, cue.kind != .whistle else { return single }

        let offset = duration(of: single) + repetitionGap
        let repeated = single.map {
            HapticPulse(
                start: $0.start + offset,
                duration: $0.duration,
                intensity: $0.intensity,
                sharpness: $0.sharpness
            )
        }

        return single + repeated
    }

    /// Seconds from the first pulse starting to the last one ending.
    static func duration(of pulses: [HapticPulse]) -> TimeInterval {
        pulses.map(\.end).max() ?? 0
    }

    /// The pattern described in words, for the learning screen to say aloud.
    static func explanation(for kind: EventCueKind) -> String {
        switch kind {
        case .goal:
            "Gol: uma vibração longa e forte."
        case .yellowCard:
            "Cartão amarelo: duas vibrações curtas, de força média."
        case .redCard:
            "Cartão vermelho: duas vibrações curtas e fortes, seguidas de uma longa."
        case .substitution:
            "Substituição: três vibrações rápidas e leves."
        case .penalty:
            "Pênalti perdido: uma vibração que vai crescendo."
        case .varReview:
            "Decisão do VAR: uma vibração contínua e leve."
        case .whistle:
            "Início ou fim de tempo: uma vibração curta e leve."
        }
    }

    /// The rule for telling the sides apart, said once on the learning screen.
    static let sideRule = "O sinal toca uma vez para o mandante e duas vezes para o visitante."
}
