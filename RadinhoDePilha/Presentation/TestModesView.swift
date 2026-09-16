import SwiftUI

/// Diagnostic modes for the API integration phase.
///
/// Exists because the artefact has to be exercised before a real Série B match is available to
/// point it at. The free plan reaches only seasons 2022 to 2024, and the evaluation with users is
/// scheduled independently of the fixture list, so "wait for a live match" is not a workable way
/// to develop or to demonstrate.
///
/// These are development instruments, not features of the finished product. They are kept on their
/// own screen, plainly labelled, so nothing here is mistaken for part of the experience under
/// evaluation.
struct TestModesView: View {
    let recordedMatch: Match?
    @Bindable var settings: AppSettings
    let speech: any SpeechService

    @State private var dump = MatchDumpModel()

    var body: some View {
        NavigationStack {
            Form {
                dumpSection
                simulateSection
                liveSection
            }
            .navigationTitle("Modos de teste")
        }
    }

    // MARK: - Periodic dump

    private var dumpSection: some View {
        Section {
            Button {
                dump.toggle(match: recordedMatch)
            } label: {
                Label(
                    dump.isRunning ? "Parar o despejo" : "Despejar a cada 3 minutos",
                    systemImage: dump.isRunning ? "stop.fill" : "doc.text.magnifyingglass"
                )
            }
            .disabled(recordedMatch == nil)

            if !dump.snapshots.isEmpty {
                ForEach(dump.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(snapshot.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Despejo periódico")
        } footer: {
            Text(
                """
                Percorre a partida gravada em passos de 3 minutos e registra placar, situação e \
                lances conhecidos em cada ponto. Serve para conferir o mapeamento dos dados sem \
                gastar requisição da API.
                """
            )
        }
    }

    // MARK: - Simulated live match

    private var simulateSection: some View {
        Section {
            NavigationLink {
                SimulatedMatchView(base: recordedMatch, settings: settings, speech: speech)
            } label: {
                Label("Simular partida ao vivo", systemImage: "play.circle")
            }
            .disabled(recordedMatch == nil)
        } header: {
            Text("Simulação")
        } footer: {
            Text(
                """
                Reproduz a partida gravada liberando um minuto de jogo por vez, como se estivesse \
                acontecendo agora. É assim que a narração ao vivo e a fila de prioridade podem ser \
                ouvidas antes de existir um jogo real para acompanhar.
                """
            )
        }
    }

    // MARK: - Real live match

    private var liveSection: some View {
        Section {
            Button {
                // Intentionally empty: enabled only once a paid plan exists.
            } label: {
                Label("Reproduzir partida ao vivo", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(true)
        } header: {
            Text("Ao vivo de verdade")
        } footer: {
            Text(
                """
                Indisponível no plano gratuito, que só alcança as temporadas de 2022 a 2024 e \
                permite 100 consultas por dia — menos do que uma única partida consome \
                consultando uma vez por minuto, como o fornecedor recomenda.
                """
            )
        }
    }
}

// MARK: - Dump model

/// Walks a recorded match in fixed steps and records what the app would know at each one.
@MainActor
@Observable
final class MatchDumpModel {
    /// One reading of the match at a given minute.
    struct Snapshot: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private(set) var snapshots: [Snapshot] = []
    private(set) var isRunning = false

    /// Match minutes between readings, as specified for this testing phase.
    private let step = 3

    func toggle(match: Match?) {
        if isRunning {
            isRunning = false
            return
        }

        guard let match else { return }

        snapshots = []
        isRunning = true
        run(match: match)
        isRunning = false
    }

    private func run(match: Match) {
        let simulator = SimulatedLiveMatchProvider(
            base: match,
            startMinute: 0,
            secondsPerMatchMinute: 1,
            startedAt: Date(timeIntervalSince1970: 0)
        )
        let engine = TemplateNarrationEngine()

        // Derived from a fixed origin rather than the wall clock, so the same match always yields
        // the same dump — a diagnostic that changed between runs would be useless for comparison.
        for minute in stride(from: 0, through: 95, by: step) {
            let state = simulator.state(
                at: Date(timeIntervalSince1970: TimeInterval(minute))
            )
            let latest = state.events.last.flatMap { engine.narrate($0, in: state) }

            snapshots.append(
                Snapshot(
                    title: "\(minute)' — \(state.homeTeam.shortName) \(state.score.home) × \(state.score.away) \(state.awayTeam.shortName)",
                    body: """
                    \(state.status.spokenDescription) · \(state.events.count) lances conhecidos
                    \(latest?.text ?? "sem lances ainda")
                    """
                )
            )
        }
    }
}
