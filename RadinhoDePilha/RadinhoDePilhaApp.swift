import SwiftUI

@main
struct RadinhoDePilhaApp: App {
    /// Composition root: the single place that decides where match data comes from.
    ///
    /// This is the payoff of ADR-001. Switching from recorded data to API-Football, or to a
    /// different vendor, is a change here and nowhere else. The screens, the narration engine and
    /// their tests never learn which provider won.
    ///
    /// Today it replays Náutico 4×3 Tombense, a real Série B match, decoded from a recorded
    /// API-Football response, as if it were happening now. Live data waits on a paid plan: the
    /// free tier only reaches seasons 2022 to 2024, so the current season cannot be requested at
    /// all, and its hundred daily requests would not survive one polled match regardless.
    private let provider: MatchDataProvider
    private let matchID: String

    /// The recorded match itself, handed to the testing screens so they can replay it at their own
    /// pace rather than sharing the main screen's clock.
    private let recordedMatch: Match?

    private let speech = AVSpeechService()
    private let settings = AppSettings()

    /// Short because the replay compresses match time. The 60-second default in the view model
    /// follows the vendor's guidance and applies when real data arrives.
    private let pollInterval = Duration.seconds(2)

    init() {
        // Falling back keeps the app demonstrable even if the recording fails to load: silence
        // would be indistinguishable from a crash for the audience this is built for.
        let recorded = try? RecordedMatches.match(named: RecordedMatches.nauticoTombense)
        let base = recorded ?? SampleMatches.liveComeback

        recordedMatch = recorded
        provider = SimulatedLiveMatchProvider(base: base, startMinute: 60)
        matchID = base.id
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                settings: settings,
                viewModel: MatchNarrationViewModel(
                    provider: provider,
                    engine: TemplateNarrationEngine(persona: settings.persona),
                    speech: speech,
                    pollInterval: pollInterval
                ),
                speech: speech,
                matchID: matchID,
                recordedMatch: recordedMatch
            )
        }
    }
}
