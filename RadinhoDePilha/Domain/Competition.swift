import Foundation

/// A competition the app knows how to follow.
///
/// Modelled as a closed set in the domain instead of a raw provider identifier. API-Football
/// identifies Série B as `72`, but that number is an implementation detail of one provider:
/// letting it reach view models would mean the presentation layer knows about the vendor, and
/// switching providers would ripple through the whole app. Each adapter keeps its own
/// translation table from these cases to whatever the vendor expects.
nonisolated enum Competition: String, Hashable, Sendable, CaseIterable {
    case brasileiraoSerieA
    case brasileiraoSerieB
    case brasileiraoSerieC

    /// State championship of Pernambuco.
    ///
    /// Present although the app follows only Série B, because recorded matches used for
    /// demonstration come from it. Representing a Pernambucano fixture as Série B would put a
    /// false statement into the domain, and the narration reads the competition name aloud.
    case pernambucano

    /// Human-readable name, in Brazilian Portuguese, for narration and accessibility labels.
    var displayName: String {
        switch self {
        case .brasileiraoSerieA: "Campeonato Brasileiro Série A"
        case .brasileiraoSerieB: "Campeonato Brasileiro Série B"
        case .brasileiraoSerieC: "Campeonato Brasileiro Série C"
        case .pernambucano: "Campeonato Pernambucano"
        }
    }
}
