import Foundation

/// A spoken sentence produced from a match event, ready to be synthesised.
nonisolated struct Narration: Identifiable, Hashable, Sendable {
    /// Identifier of the event this narration describes.
    ///
    /// Doubles as the narration's own identity: one event yields one narration, and reusing
    /// the event identifier is what lets the app tell whether something has already been
    /// spoken across polling cycles.
    let id: String

    /// Sentence in Brazilian Portuguese, meant to be heard rather than read.
    let text: String

    let priority: NarrationPriority

    /// Minute the narrated event took place, for on-screen listing and replay.
    let minute: Int

    /// Stoppage minute, when the event happened during added time.
    let stoppageMinute: Int?
}

/// Turns match data into spoken narration.
///
/// This is the semantic translation layer, the central contribution of the project: it takes
/// structured data that describes what happened and produces flowing, contextualised
/// commentary. The distinction from a fragmented notification is the point. "Gol - Marquinhos
/// 37'" states a fact; "Marquinhos empata o jogo para o Náutico" tells the listener what it
/// means for the match.
///
/// Declared as a protocol so that a future implementation backed by a language model can
/// replace the template-based one without touching the view models, and so that both can be
/// compared under the same tests during evaluation.
nonisolated protocol NarrationEngine: Sendable {
    /// Produces narration for a single event within the context of its match.
    ///
    /// Returns `nil` when the event carries nothing worth speaking. Silence is a valid
    /// outcome: narrating everything would flood the only channel the listener has.
    ///
    /// - Parameters:
    ///   - event: the event to narrate.
    ///   - match: the match the event belongs to, used to derive context such as the score at
    ///     the time and which side was ahead.
    func narrate(_ event: MatchEvent, in match: Match) -> Narration?

    /// States where the match currently stands, in one spoken passage.
    ///
    /// This is what a commentator gives someone who has just tuned in: the score, the stage of
    /// the match, and who scored. It exists as a separate concept from ``narrate(_:in:)`` because
    /// it describes a *state* rather than an *occurrence*, and because replaying the whole event
    /// list would be both long and, for a listener with no screen, harder to hold in memory than
    /// a single summary.
    func summary(of match: Match) -> Narration
}

nonisolated extension NarrationEngine {
    /// Produces narration for several events, in the order they should be spoken.
    ///
    /// Sorted by priority first and chronology second, so that a goal scored at minute 66
    /// precedes a substitution made at minute 61 when both arrive in the same polling cycle.
    func narrate(_ events: [MatchEvent], in match: Match) -> [Narration] {
        events
            .compactMap { narrate($0, in: match) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return (lhs.minute, lhs.stoppageMinute ?? 0) < (rhs.minute, rhs.stoppageMinute ?? 0)
            }
    }
}
