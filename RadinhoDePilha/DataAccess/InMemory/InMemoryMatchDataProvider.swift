import Foundation

/// Provider backed by hand-built data held in memory.
///
/// Exists so that everything above the data layer can be developed and tested without a
/// network, without credentials, and without spending request quota. It is also what makes the
/// narration engine testable at all: assertions read in the vocabulary of football rather than
/// in the shape of somebody's JSON.
///
/// This is not a throwaway test double. It is the reference implementation of
/// ``MatchDataProvider``, and the fact that the rest of the app cannot tell it apart from the
/// live provider is the practical evidence that the seam described in ADR-001 holds.
nonisolated struct InMemoryMatchDataProvider: MatchDataProvider {
    private let matches: [Match]

    /// Optional artificial delay, to exercise loading states in the interface.
    private let latency: Duration

    init(matches: [Match], latency: Duration = .zero) {
        self.matches = matches
        self.latency = latency
    }

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        try await simulateLatency()

        return matches.filter {
            $0.competition == competition && $0.season == season && $0.isLive
        }
    }

    func match(withID id: String) async throws -> Match {
        try await simulateLatency()

        guard let match = matches.first(where: { $0.id == id }) else {
            throw MatchDataError.matchNotFound(id: id)
        }

        return match
    }

    private func simulateLatency() async throws {
        guard latency > .zero else { return }
        try await Task.sleep(for: latency)
    }
}
