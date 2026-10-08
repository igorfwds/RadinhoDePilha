import Foundation

/// Category of a non-verbal signal.
///
/// Coarser than ``MatchEventKind`` on purpose. A signal has to be told apart by ear or by touch in
/// under a second, and a listener can hold only a handful of distinct motifs: a goal, an own goal
/// and a converted penalty all mean "the score changed", so they share one.
nonisolated enum EventCueKind: String, Hashable, Sendable, CaseIterable {
    case goal
    case yellowCard
    case redCard
    case substitution
    case penalty
    case varReview
    case whistle

    /// Name for the learning screen, in Brazilian Portuguese.
    var displayName: String {
        switch self {
        case .goal: "Gol"
        case .yellowCard: "Cartão amarelo"
        case .redCard: "Cartão vermelho"
        case .substitution: "Substituição"
        case .penalty: "Pênalti perdido"
        case .varReview: "Decisão do VAR"
        case .whistle: "Início ou fim de tempo"
        }
    }
}

/// Which of the two sides a signal refers to.
nonisolated enum MatchSide: String, Hashable, Sendable, CaseIterable {
    case home
    case away
}

/// A sound and a vibration announcing a match event, ahead of the sentence that describes it.
///
/// Speech is serial and slow: the listener learns what happened only as the sentence unfolds. A cue
/// carries the category of the event, and which side it belongs to, in a fraction of a second, so
/// the sentence that follows is heard already knowing what kind of news it is.
nonisolated struct EventCue: Hashable, Sendable {
    let kind: EventCueKind
    let side: MatchSide

    init(kind: EventCueKind, side: MatchSide) {
        self.kind = kind
        self.side = side
    }

    /// Derives the cue for an event, or `nil` when the event has no signal of its own.
    init?(event: MatchEvent, in match: Match) {
        let resolved: EventCueKind

        switch event.kind {
        case .goal, .ownGoal, .penaltyScored:
            resolved = .goal
        case .penaltyMissed:
            resolved = .penalty
        case .yellowCard:
            resolved = .yellowCard
        case .secondYellowCard, .redCard:
            resolved = .redCard
        case .substitution:
            resolved = .substitution
        case .varDecision:
            resolved = .varReview
        case .periodStart, .periodEnd:
            resolved = .whistle
        case .corner, .foul, .offside, .unknown:
            // Too frequent to signal: thirty fouls a match would turn the cue into noise, and
            // each one would delay its own sentence.
            return nil
        }

        // A whistle belongs to the match rather than to a side, so it is never doubled.
        let isAwaySide = resolved != .whistle && event.team.id == match.awayTeam.id

        self.init(kind: resolved, side: isAwaySide ? .away : .home)
    }
}
