import SwiftUI

/// Teaches the signals, one at a time.
///
/// A vocabulary nobody has been taught is noise. This screen plays each signal on request and then
/// says what it means, so the listener can go through the set before a match and come back to it
/// whenever one of them is not recognised.
///
/// Each row plays the sound and the vibration together, exactly as they arrive during a match,
/// even when one of the two is switched off in the settings: this is the place to find out what
/// each channel is like before deciding.
struct CueLearningView: View {
    let cues: EventCueCenter
    let speech: any SpeechService

    /// Side the examples are played for, since repetition is what tells the two apart.
    @State private var side = MatchSide.home

    var body: some View {
        Form {
            Section {
                Picker("Time do exemplo", selection: $side) {
                    Text("Mandante").tag(MatchSide.home)
                    Text("Visitante").tag(MatchSide.away)
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Escolhe para qual time os exemplos abaixo vão tocar")
            } header: {
                Text("Time")
            } footer: {
                Text(HapticGrammar.sideRule)
            }

            Section {
                ForEach(EventCueKind.allCases, id: \.self) { kind in
                    Button {
                        Task { await demonstrate(kind) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.displayName)
                                .font(.body.weight(.semibold))
                            Text(HapticGrammar.explanation(for: kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.displayName)
                    .accessibilityHint("Toque duas vezes para ouvir e sentir este sinal")
                }
            } header: {
                Text("Sinais")
            } footer: {
                Text("Cada sinal toca primeiro, e a explicação é falada em seguida.")
            }
        }
        .navigationTitle("Aprender os sinais")
    }

    /// Plays the signal, then says what it stands for.
    ///
    /// In that order on purpose: hearing the explanation first would tell the listener what to
    /// expect, and the point is to learn to recognise the signal without being told.
    private func demonstrate(_ kind: EventCueKind) async {
        await cues.demonstrate(EventCue(kind: kind, side: side))
        await speech.speakNow(HapticGrammar.explanation(for: kind), priority: .high)
    }
}

#Preview("Aprender os sinais") {
    NavigationStack {
        CueLearningView(cues: EventCueCenter(), speech: AVSpeechService())
    }
}
