import Foundation

/// How urgently a narration should reach the listener.
///
/// Exists because narration is a serial channel: only one sentence can be spoken at a time,
/// and a live match can produce several events within the same polling cycle. When that
/// happens the app has to decide what is spoken first and what may be interrupted, and doing
/// that by arrival order would let a substitution delay a goal.
nonisolated enum NarrationPriority: Int, Comparable, Hashable, Sendable {
    /// Contextual information. Spoken only when nothing else is queued.
    case low

    /// Ordinary match events: substitutions, period boundaries.
    case normal

    /// Events that change the disciplinary picture: cards, VAR reviews.
    case high

    /// Events that change the score. May interrupt speech in progress.
    case critical

    static func < (lhs: NarrationPriority, rhs: NarrationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
