import Foundation

/// Something waiting to be spoken.
nonisolated struct PendingUtterance: Hashable, Sendable {
    let id: String
    let text: String
    let priority: NarrationPriority

    /// Whether the listener asked for this specific utterance, rather than it arriving from the
    /// match.
    ///
    /// Kept apart from ``priority`` because it answers a different question. Priority ranks what
    /// matters most in the match; this ranks what the person just asked for. A tap has to be
    /// answered immediately even though a goal outranks it, otherwise the interface feels dead.
    var isOnDemand = false
}

/// Ordered set of utterances waiting for the synthesiser.
///
/// A separate type rather than an array inside the speech service, because the ordering rules are
/// the interesting part and they deserve to be testable without audio hardware, without real time
/// passing, and without a simulator.
///
/// Ordering puts anything requested by the listener first, then priority, then arrival. A goal that
/// arrives after a substitution is spoken before it; two goals arriving together are spoken in the
/// order they happened; and a moment the listener tapped is spoken before either.
nonisolated struct SpeechQueue: Sendable {
    private var items: [PendingUtterance] = []

    init() {}

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// Contents in the order they will be spoken. For inspection and tests.
    var pending: [PendingUtterance] { items }

    mutating func enqueue(_ utterance: PendingUtterance) {
        items.append(utterance)
    }

    /// Removes and returns the most urgent utterance.
    mutating func takeNext() -> PendingUtterance? {
        guard !items.isEmpty else { return nil }

        var chosen = items.startIndex

        for index in items.indices where isMoreUrgent(items[index], than: items[chosen]) {
            chosen = index
        }

        return items.remove(at: chosen)
    }

    /// Whether one utterance should be spoken before another.
    ///
    /// Strict comparison in both clauses, so equal candidates keep their arrival order.
    private func isMoreUrgent(_ candidate: PendingUtterance, than current: PendingUtterance) -> Bool {
        if candidate.isOnDemand != current.isOnDemand {
            return candidate.isOnDemand
        }

        return candidate.priority > current.priority
    }

    mutating func removeAll() {
        items.removeAll()
    }

    /// Drops anything the listener previously asked for.
    ///
    /// Used when they ask for something else. Tapping a second moment means they no longer want
    /// the first, and queueing both would make every tap add to a backlog they have to sit
    /// through. Match events are untouched: discarding a goal because somebody replayed a card
    /// would lose it for good.
    mutating func removeOnDemand() {
        items.removeAll(where: \.isOnDemand)
    }

    /// Drops queued utterances below the given priority.
    ///
    /// Used when a burst of events arrives at once: after a goal, a substitution from four minutes
    /// ago has lost most of its value, and speaking it delays whatever comes next. Keeping the
    /// threshold as a parameter leaves the policy to the caller rather than burying it here.
    mutating func discardBelow(_ priority: NarrationPriority) {
        items.removeAll { $0.priority < priority && !$0.isOnDemand }
    }
}
