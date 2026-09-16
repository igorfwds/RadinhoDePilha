import SwiftUI

/// Replays a recorded match as if it were happening now.
///
/// Reuses ``MatchNarrationView`` deliberately, the same screen, the same view model, the same
/// narration path. A simulation that ran through different code would prove nothing about the app
/// people will actually use.
///
/// What differs is only the provider and the clock, which is the seam ADR-001 exists to provide.
struct SimulatedMatchView: View {
    let base: Match?
    @Bindable var settings: AppSettings
    let speech: any SpeechService

    /// Real seconds per minute of match time.
    ///
    /// Adjustable because the two things worth testing pull in opposite directions: hearing the
    /// whole match through wants speed, while judging whether the pacing feels like radio wants
    /// something near real time.
    @State private var secondsPerMinute: Double = 2
    @State private var session: Session?

    var body: some View {
        Group {
            if let session {
                MatchNarrationView(viewModel: session.viewModel, settings: settings, matchID: session.matchID)
            } else {
                setup
            }
        }
        .navigationTitle("Simulação")
    }

    private var setup: some View {
        Form {
            Section {
                Picker("Ritmo", selection: $secondsPerMinute) {
                    Text("Rápido, 1s por minuto").tag(1.0)
                    Text("Médio, 2s por minuto").tag(2.0)
                    Text("Lento, 5s por minuto").tag(5.0)
                    Text("Tempo real, 60s por minuto").tag(60.0)
                }
                .pickerStyle(.inline)
            } header: {
                Text("Velocidade da simulação")
            } footer: {
                Text("A 2 segundos por minuto, uma partida inteira leva cerca de três minutos.")
            }

            Section {
                Button {
                    start()
                } label: {
                    Label("Começar a simulação", systemImage: "play.fill")
                }
                .disabled(base == nil)
            } footer: {
                if let base {
                    Text(
                        """
                        \(base.homeTeam.shortName) × \(base.awayTeam.shortName), \
                        \(base.events.count) lances gravados da API-Football.
                        """
                    )
                } else {
                    Text("Nenhuma partida gravada disponível.")
                }
            }
        }
    }

    private func start() {
        guard let base else { return }

        // Starts at kick-off, unlike the main screen: the point of the simulation is to hear the
        // match unfold from the beginning, including the events the catch-up would silence.
        let provider = SimulatedLiveMatchProvider(
            base: base,
            startMinute: 0,
            secondsPerMatchMinute: secondsPerMinute
        )

        let viewModel = MatchNarrationViewModel(
            provider: provider,
            engine: TemplateNarrationEngine(persona: settings.persona),
            speech: speech,
            // Polls roughly once per simulated minute, so no event waits long to be noticed.
            pollInterval: .milliseconds(Int(secondsPerMinute * 1000))
        )

        session = Session(viewModel: viewModel, matchID: base.id)
    }

    /// A running simulation. Held as one value so starting replaces both parts at once.
    private struct Session {
        let viewModel: MatchNarrationViewModel
        let matchID: String
    }
}
