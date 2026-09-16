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

/// Utterances waiting for the synthesiser.
///
/// A separate type rather than an array inside the speech service, because the ordering rules are
/// the interesting part and they deserve to be testable without audio hardware, without real time
/// passing, and without a simulator.
///
/// ## Why match events are strictly chronological
///
/// They were once ordered by priority, so a goal reported in the same polling cycle as an earlier
/// booking was spoken first. Heard rather than read, that is disorienting: commentary is a
/// narrative, and the sentences carry the running score inside them, so hearing them out of order
/// means hearing the score move backwards.
///
/// Priority survives for the two jobs it is actually good at: deciding what may cut off speech in
/// progress, and what may be dropped when the queue floods. It no longer reorders the timeline.
/// Events leave this queue in the order they arrived, which is the order they happened.
///
/// Anything the listener asked for still jumps ahead of everything, because a control that answers
/// late reads as a control that did nothing.
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

    /// Puts an utterance at the front, ahead of everything waiting.
    ///
    /// Used to restart a sentence that was cut off by a settings change: the listener changed the
    /// speed or the voice mid-sentence, and hearing that sentence again at the new setting is the
    /// point. Dropping it would lose the moment; finishing it at the old setting would make the
    /// control feel like it did nothing.
    mutating func prepend(_ utterance: PendingUtterance) {
        items.insert(utterance, at: items.startIndex)
    }

    /// Removes and returns the next utterance: a listener request if one is waiting, otherwise the
    /// oldest match event.
    mutating func takeNext() -> PendingUtterance? {
        guard !items.isEmpty else { return nil }

        let index = items.firstIndex(where: \.isOnDemand) ?? items.startIndex

        return items.remove(at: index)
    }

    mutating func removeAll() {
        items.removeAll()
    }

    /// Drops anything the listener previously asked for.
    ///
    /// Used when they ask for something else. Tapping a second moment means they no longer want
    /// the first, and queueing both would make every tap add to a backlog they have to sit through.
    mutating func removeOnDemand() {
        items.removeAll(where: \.isOnDemand)
    }

    /// Keeps only the most recent match event, discarding the ones queued behind it.
    ///
    /// Called when the listener interrupts. While they were asking for something else the match
    /// carried on, and returning to a backlog of stale commentary is not what "live" means. They
    /// want where the match *is*, not a recap of the seconds they missed. The newest event is kept
    /// rather than none, so resuming says something instead of falling silent.
    ///
    /// Requests are untouched: this discards the match's queue, not the listener's.
    mutating func keepOnlyLatestEvent() {
        guard let latest = items.last(where: { !$0.isOnDemand }) else { return }

        items.removeAll { !$0.isOnDemand && $0 != latest }
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
