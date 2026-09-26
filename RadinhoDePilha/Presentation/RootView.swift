import SwiftUI

/// Top-level navigation.
///
/// A tab bar rather than a stack of pushes, because tabs are flat: a screen reader user reaches
/// any section from anywhere with one gesture, and never has to work out how deep they are or how
/// to get back. For an app used while attention is on a match rather than on the screen, that
/// predictability is worth more than visual economy.
///
/// Narração comes first and is the default, since it is the reason the app exists. Settings sit
/// last, where the platform trains people to look for them.
///
/// This view also owns **which match is being followed**, because that can change from elsewhere:
/// the live lookup on the testing screen replaces it and brings the narration tab forward.
struct RootView: View {
    @State private var settings: AppSettings
    @State private var viewModel: MatchNarrationViewModel

    /// Match currently on the narration screen.
    @State private var followedMatchID: String

    @State private var selectedTab = Tab.narration

    private let speech: any SpeechService
    private let recordedMatch: Match?

    /// Live data source, or `nil` without a credential.
    private let liveProvider: APIFootballProvider?

    /// Gap between polls when following a real match.
    private let livePollInterval: Duration

    private enum Tab: Hashable {
        case narration
        case modes
        case settings
    }

    init(
        settings: AppSettings,
        viewModel: MatchNarrationViewModel,
        speech: any SpeechService,
        matchID: String,
        recordedMatch: Match?,
        liveProvider: APIFootballProvider?,
        livePollInterval: Duration
    ) {
        self.settings = settings
        self.viewModel = viewModel
        self.speech = speech
        self.followedMatchID = matchID
        self.recordedMatch = recordedMatch
        self.liveProvider = liveProvider
        self.livePollInterval = livePollInterval
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab(
                "Narração",
                systemImage: "dot.radiowaves.left.and.right",
                value: Tab.narration
            ) {
                MatchNarrationView(
                    viewModel: viewModel,
                    settings: settings,
                    matchID: followedMatchID
                )
                // A new identity per match. The screen keeps its view model in `@State`, which
                // SwiftUI preserves across updates, so without this the old session would stay on
                // screen after a live match replaced it.
                .id(followedMatchID)
            }

            SwiftUI.Tab("Modos", systemImage: "slider.horizontal.3", value: Tab.modes) {
                TestModesView(
                    recordedMatch: recordedMatch,
                    settings: settings,
                    speech: speech,
                    liveProvider: liveProvider,
                    onFollowLiveMatch: follow(liveMatch:)
                )
            }

            SwiftUI.Tab("Ajustes", systemImage: "gearshape", value: Tab.settings) {
                SettingsView(settings: settings, speech: speech)
            }
        }
        // Applied at the root so every screen honours the choice, including the ones that only
        // exist for testing. Left untouched when the listener follows the system, rather than
        // overridden with a value that would silently replace their own setting.
        .modifier(TextSizeOverride(size: settings.textSize.dynamicTypeSize))
        // Held only while narrating, and released when the app leaves the foreground.
        .keepsScreenAwake(viewModel.isNarrating)
        .task {
            // Configures the audio session before the first utterance, so the first goal is not
            // the one that pays for the setup.
            await speech.activate()
            await applySettings()
        }
        .onChange(of: settings.persona) {
            viewModel.setPersona(settings.persona)
        }
        .onChange(of: settings.rate) {
            Task { await speech.setRate(settings.rate) }
        }
        .onChange(of: settings.voiceIdentifier) {
            Task { await speech.setVoice(identifier: settings.voiceIdentifier) }
        }
    }

    /// Switches the narration screen to a live match and brings it forward.
    ///
    /// Moving to the tab is part of the answer, not decoration: the listener asked to hear a match,
    /// and starting audio while leaving them on another screen would be disorienting for someone
    /// navigating by screen reader.
    ///
    /// The session is replaced, not redirected. The screen used to receive only the new match
    /// identifier while its view model still pointed at the recorded replay, so it looked the live
    /// match up in a 2022 recording, failed, and showed an error at the one moment it mattered.
    /// It also polled every two seconds, a pace chosen for compressed replay time.
    private func follow(liveMatch match: Match) {
        guard let liveProvider else { return }

        Task {
            // Stops the replay and empties the queue, so nothing from 2022 is spoken over the
            // live match.
            await viewModel.stopNarrating()

            let live = MatchNarrationViewModel(
                provider: liveProvider,
                engine: TemplateNarrationEngine(persona: settings.persona),
                speech: speech,
                pollInterval: livePollInterval
            )
            live.startAfterLoading()

            viewModel = live
            followedMatchID = match.id
            selectedTab = .narration
        }
    }

    /// Pushes stored preferences into the services on launch.
    ///
    /// Necessary because the services start at their own defaults; without this, a listener who
    /// chose the analytical persona last week would hear the classic one until they touched the
    /// setting again.
    private func applySettings() async {
        viewModel.setPersona(settings.persona)
        await speech.setRate(settings.rate)
        await speech.setVoice(identifier: settings.voiceIdentifier)
    }
}

/// Forces a text size, or leaves the system's choice alone when none is given.
///
/// `dynamicTypeSize` takes a non-optional, so "follow the system" cannot be expressed by passing
/// `nil` to it. Branching here keeps that distinction where it belongs instead of pushing callers
/// to invent a sentinel value.
private struct TextSizeOverride: ViewModifier {
    let size: DynamicTypeSize?

    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
