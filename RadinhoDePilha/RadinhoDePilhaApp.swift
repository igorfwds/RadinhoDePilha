import SwiftUI

@main
struct RadinhoDePilhaApp: App {
    /// Composition root: the single place that decides where match data comes from.
    ///
    /// This is the payoff of ADR-001. Switching from recorded data to API-Football, or to a
    /// different vendor, is a change here and nowhere else. The screens, the narration engine and
    /// their tests never learn which provider won.
    ///
    /// The narration tab opens on Náutico 4×3 Tombense, a real Série B match decoded from a recorded
    /// API-Football response and replayed as if it were happening now. Live data takes over when
    /// the live lookup finds a match in progress; see `RootView.follow(liveMatch:)`.
    private let provider: MatchDataProvider
    private let matchID: String

    /// The recorded match itself, handed to the testing screens so they can replay it at their own
    /// pace rather than sharing the main screen's clock.
    private let recordedMatch: Match?

    private let speech = AVSpeechService()
    private let settings = AppSettings()

    /// Live data, available once a credential is configured.
    private let liveProvider: APIFootballProvider? = AppConfiguration.apiFootballKey.map {
        APIFootballProvider(apiKey: $0)
    }

    /// Fifteen seconds, the vendor's own refresh interval.
    ///
    /// Polling faster buys nothing, since the data does not change more often. Polling at the one
    /// call per minute the vendor recommends would delay a goal by up to a minute, which is long
    /// for someone following by ear. At fifteen seconds a match costs about 450 requests, well
    /// inside the Pro plan's 7,500 a day, and four calls a minute is nowhere near its limit of 300.
    private let livePollInterval = Duration.seconds(15)

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
                recordedMatch: recordedMatch,
                liveProvider: liveProvider,
                livePollInterval: livePollInterval
            )
        }
    }
}
