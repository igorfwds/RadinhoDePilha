import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Speech queue")
struct SpeechQueueTests {
    private func utterance(
        _ id: String,
        _ priority: NarrationPriority,
        onDemand: Bool = false
    ) -> PendingUtterance {
        PendingUtterance(
            id: id,
            text: "texto \(id)",
            priority: priority,
            isOnDemand: onDemand
        )
    }

    @Test("What the listener asked for outranks even a goal")
    func onDemandOutranksEverything() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("gol", .critical))
        queue.enqueue(utterance("pedido", .normal, onDemand: true))

        #expect(queue.takeNext()?.id == "pedido")
        // The goal is not discarded, only made to wait.
        #expect(queue.takeNext()?.id == "gol")
    }

    @Test("Asking for something else drops the earlier request but keeps match events")
    func removingOnDemandSparesEvents() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("gol", .critical))
        queue.enqueue(utterance("primeiro-pedido", .normal, onDemand: true))

        queue.removeOnDemand()

        #expect(queue.count == 1)
        #expect(queue.takeNext()?.id == "gol")
    }

    @Test("Discarding by priority never drops what the listener asked for")
    func discardBelowSparesOnDemand() {
        // A replayed substitution was explicitly requested, so a burst of events must not
        // silently swallow it.
        var queue = SpeechQueue()
        queue.enqueue(utterance("pedido", .low, onDemand: true))
        queue.enqueue(utterance("substituicao", .normal))

        queue.discardBelow(.high)

        #expect(queue.count == 1)
        #expect(queue.takeNext()?.id == "pedido")
    }

    @Test("An empty queue yields nothing")
    func emptyQueueYieldsNothing() {
        var queue = SpeechQueue()

        #expect(queue.takeNext() == nil)
        #expect(queue.isEmpty)
    }

    @Test("The most urgent utterance comes out first")
    func mostUrgentComesFirst() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("sub", .normal))
        queue.enqueue(utterance("goal", .critical))
        queue.enqueue(utterance("card", .high))

        #expect(queue.takeNext()?.id == "goal")
        #expect(queue.takeNext()?.id == "card")
        #expect(queue.takeNext()?.id == "sub")
        #expect(queue.isEmpty)
    }

    @Test("Equal priorities keep arrival order")
    func equalPrioritiesKeepArrivalOrder() {
        // Two goals in the same polling cycle must be spoken in the order they happened, otherwise
        // the listener hears the second goal announced before the first.
        var queue = SpeechQueue()
        queue.enqueue(utterance("first", .critical))
        queue.enqueue(utterance("second", .critical))

        #expect(queue.takeNext()?.id == "first")
        #expect(queue.takeNext()?.id == "second")
    }

    @Test("A late arrival of higher priority overtakes what is waiting")
    func lateHighPriorityOvertakes() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("sub", .normal))
        queue.enqueue(utterance("period", .normal))
        queue.enqueue(utterance("goal", .critical))

        #expect(queue.takeNext()?.id == "goal")
    }

    @Test("Discarding below a threshold keeps the important ones")
    func discardBelowKeepsImportant() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("sub", .normal))
        queue.enqueue(utterance("card", .high))
        queue.enqueue(utterance("goal", .critical))

        queue.discardBelow(.high)

        #expect(queue.count == 2)
        #expect(!queue.pending.contains { $0.id == "sub" })
    }

    @Test("Clearing empties the queue")
    func clearingEmptiesQueue() {
        var queue = SpeechQueue()
        queue.enqueue(utterance("a", .normal))
        queue.enqueue(utterance("b", .critical))

        queue.removeAll()

        #expect(queue.isEmpty)
    }
}

@Suite("Speech interruption policy")
struct SpeechInterruptionPolicyTests {
    @Test("Nothing interrupts under the never policy")
    func neverPolicyBlocksEverything() {
        let policy = SpeechInterruptionPolicy.never

        #expect(!policy.allowsInterrupting(current: .normal, with: .critical))
        #expect(!policy.allowsInterrupting(current: .low, with: .critical))
    }

    @Test("A goal interrupts a substitution")
    func goalInterruptsSubstitution() {
        let policy = SpeechInterruptionPolicy.above(.high)

        #expect(policy.allowsInterrupting(current: .normal, with: .critical))
    }

    @Test("A substitution never interrupts a goal")
    func substitutionDoesNotInterruptGoal() {
        let policy = SpeechInterruptionPolicy.above(.high)

        #expect(!policy.allowsInterrupting(current: .critical, with: .normal))
    }

    @Test("Equal priority does not interrupt")
    func equalPriorityDoesNotInterrupt() {
        // Two goals: the second waits. Cutting off the first goal's sentence would lose the
        // scoreline the listener needs.
        let policy = SpeechInterruptionPolicy.above(.high)

        #expect(!policy.allowsInterrupting(current: .critical, with: .critical))
    }

    @Test("A card does not interrupt, being at the threshold rather than above it")
    func cardAtThresholdDoesNotInterrupt() {
        let policy = SpeechInterruptionPolicy.above(.high)

        #expect(!policy.allowsInterrupting(current: .normal, with: .high))
    }
}

@Suite("Speech rate")
struct SpeechRateTests {
    @Test("Rates are ordered from slow to very fast")
    func ratesAreOrdered() {
        let multipliers = SpeechRate.allCases.map(\.multiplier)

        #expect(multipliers == multipliers.sorted())
    }

    @Test("Normal speech leaves the platform default untouched")
    func normalIsNeutral() {
        #expect(SpeechRate.normal.multiplier == 1.0)
    }

    @Test("Every rate has a spoken label", arguments: SpeechRate.allCases)
    func everyRateHasLabel(rate: SpeechRate) {
        // The settings screen reads these aloud, so an empty one would be a silent control.
        #expect(!rate.displayName.isEmpty)
    }
}
