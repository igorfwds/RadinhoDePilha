import Testing
@testable import RadinhoDePilha

/// Tests when the Sportmonks provider gives up asking for the running totals.
///
/// The totals are what corners, fouls and offsides are worked out from. Giving them up after a
/// failure that would have passed silences those plays for the rest of the session, which is what
/// a short drop in a stadium's connection did during a live match.
@Suite("Sportmonks provider")
struct SportmonksProviderTests {
    @Test(
        "A passing failure keeps the totals coming",
        arguments: [
            MatchDataError.network(underlying: "The request timed out."),
            .quotaExceeded,
            .providerFailure(status: 500),
            .providerFailure(status: 503)
        ]
    )
    func passingFailureKeepsTotals(error: MatchDataError) {
        #expect(!SportmonksProvider.shouldStopRequestingTotals(after: error))
    }

    @Test(
        "A refusal of the request gives the totals up",
        arguments: [
            MatchDataError.unauthorized,
            .providerFailure(status: 400),
            .providerFailure(status: 422),
            .decoding(underlying: "statistics is not an array")
        ]
    )
    func refusalGivesUpTotals(error: MatchDataError) {
        #expect(SportmonksProvider.shouldStopRequestingTotals(after: error))
    }

    @Test("A failure from outside the data layer keeps the totals coming")
    func foreignFailureKeepsTotals() {
        #expect(!SportmonksProvider.shouldStopRequestingTotals(after: CancellationError()))
    }
}
