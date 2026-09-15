import Foundation

/// What a goal changes for the side that scored it.
///
/// Declared at file scope rather than nested inside the engine so that the classification can be
/// asserted on directly in tests, separately from the wording. Keeping the two apart matters:
/// wording has several accepted alternatives and will keep changing, while the classification is
/// the actual logic and must not.
nonisolated enum GoalContext: Hashable, Sendable, CaseIterable {
    /// First goal of the match.
    case opensScore

    /// Brings the scoring side level.
    case equalises

    /// Breaks a tie, without the side having trailed earlier.
    case takesLead

    /// Breaks a tie after the side had been behind at some point.
    case comeback

    /// Widens a lead the side already held.
    case extendsLead

    /// Narrows a deficit the side is still under.
    case reducesDeficit
}
