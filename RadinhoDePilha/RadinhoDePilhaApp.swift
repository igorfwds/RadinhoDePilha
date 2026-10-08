import SwiftUI

@main
struct RadinhoDePilhaApp: App {
    /// Composition root: the single place that decides where match data comes from.
    ///
    /// This is the payoff of ADR-001. Switching from recorded data to API-Football, or to a
    /// different vendor, is a change here and nowhere else. The screens, the narration engine and
    /// their tests never learn which provider won.
    ///
    /// With a vendor credential configured, the narration screen follows real data, so that a
    /// live match found from the testing screen can actually be loaded and polled. The screen
    /// opens on Náutico 4×3 Tombense, a real Série B match, until the lookup replaces it. Which
    /// vendor that is, Sportmonks or API-Football, is ``LiveDataSource/configured``'s decision.
    ///
    /// Without a credential it replays that same match, decoded from a recorded response, as if it
    /// were happening now, which keeps the app demonstrable offline.
    private let provider: MatchDataProvider
    private let matchID: String

    /// The recorded match itself, handed to the testing screens so they can replay it at their own
    /// pace rather than sharing the main screen's clock.
    private let recordedMatch: Match?

    private let speech = AVSpeechService()
    private let settings = AppSettings()

    /// Gap between polls, which differs by provider.
    ///
    /// Short for the replay, which compresses match time. For a live vendor it is whatever that
    /// vendor's quota allows, which ``LiveDataSource`` knows.
    private let pollInterval: Duration

    /// Where live narration is written down, when the configured vendor is being recorded.
    private let log: MatchTimelineLog?

    init() {
        // Falling back keeps the app demonstrable even if the recording fails to load: silence
        // would be indistinguishable from a crash for the audience this is built for.
        let recorded = try? RecordedMatches.match(named: RecordedMatches.nauticoTombense)
        let base = recorded ?? SampleMatches.liveComeback

        recordedMatch = recorded
        matchID = base.id

        if let source = LiveDataSource.configured {
            // The opening match is a recording, and its identifier means nothing to a vendor
            // other than the one it was recorded from, so it is answered locally.
            provider = RecordedFirstProvider(recorded: [base], live: source.provider)
            pollInterval = source.pollInterval
            log = source.log
        } else {
            provider = SimulatedLiveMatchProvider(base: base, startMinute: 60)
            pollInterval = .seconds(2)
            log = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                settings: settings,
                viewModel: MatchNarrationViewModel(
                    provider: provider,
                    engine: TemplateNarrationEngine(persona: settings.persona),
                    speech: speech,
                    pollInterval: pollInterval,
                    log: log
                ),
                speech: speech,
                matchID: matchID,
                recordedMatch: recordedMatch
            )
        }
    }
}
