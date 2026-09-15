import SwiftUI

@main
struct RadinhoDePilhaApp: App {
    /// Composition root: the single place that decides where match data comes from.
    ///
    /// This is the payoff of ADR-001. Switching from hand-built data to API-Football, or to a
    /// different vendor, is a change to this property and to nothing else. The screens, the
    /// narration engine and their tests never learn which provider won.
    ///
    /// The simulated provider stands in until the credential exists. It starts the sample match at
    /// minute 60 so the app opens mid-match, which is the case the live loop has to get right and
    /// the one a static provider cannot exercise.
    private let provider = SimulatedLiveMatchProvider(base: SampleMatches.liveComeback)

    private let speech = AVSpeechService()

    /// Short while the clock is compressed. The API-Football plan bills per request and wants
    /// thirty seconds; three would burn the daily quota before half-time.
    private let pollInterval = Duration.seconds(2)

    var body: some Scene {
        WindowGroup {
            MatchNarrationView(
                viewModel: MatchNarrationViewModel(
                    provider: provider,
                    speech: speech,
                    pollInterval: pollInterval
                ),
                matchID: SampleMatches.liveComeback.id
            )
            .task {
                // Configures the audio session before the first utterance, so the first goal is
                // not the one that pays for the setup.
                await speech.activate()
            }
        }
    }
}
