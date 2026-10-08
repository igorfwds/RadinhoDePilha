import SwiftUI

@main
struct RadinhoDePilhaApp: App {
    /// Composition root: the single place that decides where match data comes from.
    ///
    /// This is the payoff of ADR-001. Switching from recorded data to API-Football, or to a
    /// different vendor, is a change here and nowhere else. The screens, the narration engine and
    /// their tests never learn which provider won.
    ///
    /// The narration tab opens on Náutico 3×3 Operário, a real Série B match decoded from a recorded
    /// Sportmonks response and replayed as if it were happening now. With a vendor credential
    /// configured, live data takes over: the tab opens on the matchday screen instead, and a match
    /// in progress replaces the replay; see `RootView.follow(liveMatch:)`. Which vendor that is,
    /// Sportmonks or API-Football, is ``LiveDataSource/configured``'s decision.
    private let provider: MatchDataProvider
    private let matchID: String

    /// The recorded match itself, handed to the testing screens so they can replay it at their own
    /// pace rather than sharing the main screen's clock.
    private let recordedMatch: Match?

    /// Sounds and vibrations that announce each event, shared by the voice that triggers them
    /// and by the settings screen that switches them on and off.
    private let cues: EventCueCenter

    private let speech: AVSpeechService
    private let settings = AppSettings()

    /// Live data, available once a vendor credential is configured.
    private let live = LiveDataSource.configured

    /// Short because the replay compresses match time. A live match is polled at the pace its
    /// vendor allows, which ``LiveDataSource`` knows.
    private let pollInterval = Duration.seconds(2)

    init() {
        // Falling back keeps the app demonstrable even if the recording fails to load: silence
        // would be indistinguishable from a crash for the audience this is built for.
        let recorded = try? RecordedMatches.sportmonksMatch(named: RecordedMatches.nauticoOperario)
        let base = recorded ?? SampleMatches.liveComeback

        recordedMatch = recorded
        matchID = base.id

        let cues = EventCueCenter()
        self.cues = cues
        speech = AVSpeechService(cues: cues)

        provider = SimulatedLiveMatchProvider(base: base, startMinute: 60)
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
                cues: cues,
                matchID: matchID,
                recordedMatch: recordedMatch,
                live: live
            )
        }
    }
}
