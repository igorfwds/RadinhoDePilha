import SwiftUI

/// The narration screen.
///
/// Built for someone who may not see it at all. Three consequences shape every choice here:
/// text is large by default and scales with Dynamic Type, colour never carries meaning on its own,
/// and every control states out loud what it does and what will happen.
///
/// ## Live narration outlives this screen
///
/// The polling loop is deliberately **not** stopped when this view goes away. A tab bar dismisses
/// the previous tab, so suspending here meant that visiting Ajustes silenced the match, which is
/// exactly backwards: someone adjusting the voice mid-match is adjusting it *because* they are
/// listening. Narration stops when the listener stops it, and not before.
///
/// ## Glass and low vision
///
/// The surfaces use the platform's Liquid Glass material, which is translucent by nature, and
/// translucency lowers contrast, which is the opposite of what this audience needs. The two are
/// reconciled by ``AdaptiveGlass``: glass when the system allows it, an opaque bordered surface
/// when the listener has asked to reduce transparency or raise contrast. Legibility wins whenever
/// the two are in conflict.
struct MatchNarrationView: View {
    @State private var viewModel: MatchNarrationViewModel

    /// Shared preferences, so the speed control here and the one in Ajustes are the same setting.
    ///
    /// They used to be two: this screen held its own rate and the settings screen held another,
    /// each pushing to the speech service. Whichever was touched last won, and the two pickers
    /// disagreed on screen.
    @Bindable var settings: AppSettings

    private let matchID: String

    @Namespace private var glassNamespace

    init(viewModel: MatchNarrationViewModel, settings: AppSettings, matchID: String) {
        self.viewModel = viewModel
        self.settings = settings
        self.matchID = matchID
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Radinho de Pilha")
                .background { backdrop }
                // Keyed on the identifier so that switching matches, which the live lookup does
                // from another tab, reloads instead of leaving the previous match on screen.
                .task(id: matchID) { await viewModel.load(matchID: matchID) }
        }
    }

    /// Something for the glass to refract.
    ///
    /// Glass over a flat fill reads as a grey rectangle. The gradient is built from the accent
    /// colour rather than from fixed colours so it follows light and dark appearance instead of
    /// forcing one of them.
    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.30),
                Color.accentColor.opacity(0.06),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Carregando a partida")
                .accessibilityLabel("Carregando a partida")
        } else if let message = viewModel.errorMessage {
            errorState(message)
        } else if let match = viewModel.match {
            loaded(match)
        } else {
            ContentUnavailableView(
                "Nenhuma partida",
                systemImage: "sportscourt",
                description: Text("Nenhuma partida foi carregada.")
            )
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                // Decorative: the message right below says the same thing, and VoiceOver
                // announcing "warning triangle" before it would only add noise.
                .accessibilityHidden(true)

            Text(message)
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .modifier(AdaptiveGlass(cornerRadius: 28))
        .padding()
        .accessibilityElement(children: .combine)
    }

    private func loaded(_ match: Match) -> some View {
        VStack(spacing: 0) {
            scoreboard(match)
            eventList
            controls
        }
    }

    // MARK: - Scoreboard

    private func scoreboard(_ match: Match) -> some View {
        VStack(spacing: 8) {
            Text(match.competition.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Side by side while it fits, stacked once it does not. A club name hyphenated across
            // two lines ("Náuti-co") is the first thing Dynamic Type breaks here, and this
            // audience is the one most likely to be running the largest sizes.
            ViewThatFits(in: .horizontal) {
                inlineScore(match)
                stackedScore(match)
            }

            HStack(spacing: 8) {
                if viewModel.isNarrating {
                    liveIndicator
                }

                Text(statusLine(match))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .modifier(AdaptiveGlass(cornerRadius: 28))
        .padding(.horizontal)
        .padding(.bottom, 8)
        // One element instead of five. Swiping through "Náutico", "2", "×", "1", "CRB" separately
        // forces the listener to assemble the score themselves.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardAnnouncement(match))
        .accessibilityAddTraits(.isHeader)
    }

    /// Score on one line: home, scoreline, away.
    private func inlineScore(_ match: Match) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(match.homeTeam.shortName)
                .lineLimit(1)

            Text("\(match.score.home) × \(match.score.away)")
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)

            Text(match.awayTeam.shortName)
                .lineLimit(1)
        }
        .font(.largeTitle)
    }

    /// Score as one row per side, for when the names no longer fit beside each other.
    private func stackedScore(_ match: Match) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            scoreRow(name: match.homeTeam.shortName, goals: match.score.home)
            scoreRow(name: match.awayTeam.shortName, goals: match.score.away)
        }
        .font(.largeTitle)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scoreRow(name: String, goals: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)

            Spacer(minLength: 12)

            Text("\(goals)")
                .fontWeight(.bold)
                .monospacedDigit()
        }
    }

    /// Marks live narration with a shape as well as a colour.
    ///
    /// A red dot alone would carry the meaning in colour only, which fails for the many low-vision
    /// users with colour deficiency. The word next to it is what actually states it.
    private var liveIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption)
            Text("AO VIVO")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.red)
        .accessibilityHidden(true)
    }

    private func statusLine(_ match: Match) -> String {
        guard let minutes = match.elapsedMinutes, match.isLive else {
            return match.status.spokenDescription
        }
        return "\(match.status.spokenDescription), \(minutes) minutos"
    }

    /// Scoreboard as a single spoken sentence.
    private func scoreboardAnnouncement(_ match: Match) -> String {
        """
        \(match.competition.displayName). \
        \(match.homeTeam.shortName) \(match.score.home), \
        \(match.awayTeam.shortName) \(match.score.away). \
        \(statusLine(match)).\
        \(viewModel.isNarrating ? " Narrando ao vivo." : "")
        """
    }

    // MARK: - Events

    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.narrations) { narration in
                        narrationRow(narration)
                            .id(narration.id)
                    }
                }
                .padding()
            }
            .accessibilityLabel("Lances da partida")
            // Follows the match as it happens. Scrolling is not announced, so a screen-reader
            // user is unaffected; this serves whoever is watching the screen alongside.
            .onChange(of: viewModel.narrations.count) {
                guard let last = viewModel.narrations.last else { return }

                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func narrationRow(_ narration: Narration) -> some View {
        Button {
            Task { await viewModel.replay(narration) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(minuteLabel(narration))
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .leading)

                Text(narration.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(narration.text)
        // The hint states the outcome of the action, which is what a listener needs before
        // deciding to activate it.
        .accessibilityHint("Toque duas vezes para ouvir este lance novamente")
        .accessibilityAddTraits(.isButton)
    }

    private func minuteLabel(_ narration: Narration) -> String {
        if let stoppage = narration.stoppageMinute, stoppage > 0 {
            return "\(narration.minute)+\(stoppage)'"
        }
        return "\(narration.minute)'"
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    playButton
                    summaryButton
                }
            }

            Picker("Velocidade da narração", selection: $settings.rate) {
                ForEach(SpeechRate.allCases, id: \.self) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Ajusta a velocidade da voz")
        }
        .padding()
    }

    private var playButton: some View {
        Button {
            Task {
                if viewModel.isNarrating {
                    await viewModel.stopNarrating()
                } else {
                    await viewModel.startNarrating()
                }
            }
        } label: {
            Label(
                viewModel.isNarrating ? "Parar" : "Narrar ao vivo",
                systemImage: viewModel.isNarrating ? "stop.fill" : "play.fill"
            )
            .font(.title3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .glassEffectID("play", in: glassNamespace)
        // States the outcome, and states that live narration does not recount what already
        // happened, otherwise a listener joining at half-time would expect a recap and get
        // silence until the next event.
        .accessibilityHint(
            viewModel.isNarrating
                ? "Interrompe a narração em andamento"
                : "Passa a narrar os lances a partir de agora"
        )
    }

    private var summaryButton: some View {
        Button {
            Task { await viewModel.speakSummary() }
        } label: {
            Label("Resumo", systemImage: "list.bullet.rectangle")
                .font(.title3)
                .labelStyle(.iconOnly)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
        }
        .buttonStyle(.glass)
        .glassEffectID("summary", in: glassNamespace)
        .accessibilityLabel("Resumo da partida")
        .accessibilityHint("Diz o placar, o tempo de jogo e quem marcou")
    }
}

// MARK: - Adaptive surface

/// Liquid Glass, unless the listener has asked for more contrast.
///
/// `glassEffect` is translucent by design, and the system already tones it down under Reduce
/// Transparency. That is not enough here: this app's audience is defined by low vision, so the
/// fallback is an opaque surface with a visible border rather than a subtler glass. Increase
/// Contrast is honoured for the same reason.
private struct AdaptiveGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let cornerRadius: CGFloat

    private var wantsOpaqueSurface: Bool {
        reduceTransparency || contrast == .increased
    }

    func body(content: Content) -> some View {
        if wantsOpaqueSurface {
            content
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.primary, lineWidth: 2)
                }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Spoken descriptions

extension MatchStatus {
    /// Status phrased for speech, in Brazilian Portuguese.
    var spokenDescription: String {
        switch self {
        case .scheduled: "A começar"
        case .firstHalf: "Primeiro tempo"
        case .halfTime: "Intervalo"
        case .secondHalf: "Segundo tempo"
        case .extraTime: "Prorrogação"
        case .breakTime: "Intervalo da prorrogação"
        case .penaltyShootout: "Disputa de pênaltis"
        case .inProgress: "Em andamento"
        case .interrupted: "Jogo interrompido"
        case .suspended: "Jogo suspenso"
        case .finished: "Encerrada"
        case .abandoned: "Abandonada"
        case .awarded: "Decidida fora de campo"
        case .postponed: "Adiada"
        case .cancelled: "Cancelada"
        case .unknown: "Situação indefinida"
        }
    }
}

#Preview("Partida ao vivo") {
    MatchNarrationView(
        viewModel: MatchNarrationViewModel(
            provider: SimulatedLiveMatchProvider(base: SampleMatches.liveComeback),
            speech: AVSpeechService(),
            pollInterval: .seconds(2)
        ),
        settings: AppSettings(),
        matchID: SampleMatches.liveComeback.id
    )
}
