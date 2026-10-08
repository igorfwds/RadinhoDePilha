import SwiftUI

/// What the narration tab shows when no match is being followed: the countdown to the next one.
///
/// Every piece of information here reaches the listener three ways: on screen, through VoiceOver,
/// and through the app's own voice on request. The last one matters for low-vision listeners who
/// do not use VoiceOver, and it is why "Quanto falta?" and "Último resultado" exist as buttons.
struct MatchdayView: View {
    let model: MatchdayViewModel

    /// Crest size, scaled with Dynamic Type so it grows with the rest of the text.
    @ScaledMetric(relativeTo: .largeTitle) private var crestSize: CGFloat = 88

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Radinho de Pilha")
        }
        // Loads once. The tab reappears often, and each load is three requests on a day when the
        // quota is already being spent on live polling.
        .task {
            if model.phase == .loading { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading, .live:
            // `live` is handed to the narration screen by the root view; this is only the moment
            // in between.
            ProgressView("Consultando os jogos do Náutico")

        case .upcoming(let next, let last):
            scroll {
                fixtureCard(next, title: "Próximo jogo")
                countdown(until: next.kickoff)
                askButton
                lastResult(last)
            }

        case .awaitingKickoff(let next, let last):
            scroll {
                fixtureCard(next, title: "Próximo jogo")
                awaiting
                askButton
                lastResult(last)
            }

        case .noUpcoming(let last):
            scroll {
                Text("Nenhum próximo jogo do Náutico agendado.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                lastResult(last)
            }

        case .failed(let message):
            scroll {
                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await model.load() }
                } label: {
                    Label("Tentar de novo", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 24, content: content)
                .padding()
        }
    }

    // MARK: - Fixture

    private func fixtureCard(_ match: Match, title: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(match.competition.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                side(match.homeTeam)

                Text("×")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, crestSize / 3)
                    .accessibilityHidden(true)

                side(match.awayTeam)
            }
            // One element: "Náutico contra CRB" rather than two names, a symbol and two images.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(match.homeTeam.shortName) contra \(match.awayTeam.shortName)")

            Text(model.kickoffPhrase(for: match))
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }

    private func side(_ team: Team) -> some View {
        VStack(spacing: 8) {
            Crest(url: team.crestURL, size: crestSize)

            Text(team.shortName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Countdown

    /// Redraws every second for the eye, and speaks by the minute for the ear.
    ///
    /// The element ignores its children, so VoiceOver never sees the ticking digits, only the
    /// label. And it has no `updatesFrequently` trait, so a changing label is read when focused but
    /// never announced on its own.
    private func countdown(until kickoff: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let parts = CountdownParts(until: kickoff, from: context.date)

            HStack(spacing: 8) {
                unit(parts.days, "dias")
                unit(parts.hours, "horas")
                unit(parts.minutes, "min")
                unit(parts.seconds, "seg")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.countdownLabel(at: context.date))
        }
    }

    private func unit(_ value: Int, _ name: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.integerLength(2...)))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var awaiting: some View {
        VStack(spacing: 12) {
            ProgressView()
                .accessibilityHidden(true)

            Text("Aguardando o início da partida")
                .font(.title3.weight(.semibold))

            Text("O horário chegou. A narração começa sozinha assim que a bola rolar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Asking aloud

    private var askButton: some View {
        Button {
            Task { await model.speakTimeRemaining() }
        } label: {
            Label("Quanto falta?", systemImage: "speaker.wave.2.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Diz em voz alta quanto tempo falta para o jogo")
    }

    // MARK: - Last result

    @ViewBuilder
    private func lastResult(_ last: Match?) -> some View {
        if let last {
            VStack(spacing: 12) {
                Text("Último jogo")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 12) {
                    Crest(url: last.homeTeam.crestURL, size: crestSize * 0.5)
                    Text("\(last.homeTeam.shortName) \(last.score.home) × \(last.score.away) \(last.awayTeam.shortName)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Crest(url: last.awayTeam.crestURL, size: crestSize * 0.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.lastResultAnnouncement())

                Button {
                    Task { await model.speakLastResult() }
                } label: {
                    Label("Ouvir o último resultado", systemImage: "speaker.wave.2")
                }
                .accessibilityHint("Diz em voz alta o placar do último jogo")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
        }
    }
}

// MARK: - Crest

/// A club crest on a light disc with a border.
///
/// The disc is there for contrast: many crests are dark or have dark outlines, and on a dark
/// background they all but disappear for someone with low vision. Hidden from VoiceOver, since the
/// club's name is always read next to it and the image adds nothing to hear.
///
/// `AsyncImage` goes through the shared URL cache, which is what the vendor asks for: crest requests
/// do not count against the daily quota but are rate limited, and should not be repeated.
private struct Crest: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
            Circle()
                .strokeBorder(.primary.opacity(0.35), lineWidth: 2)

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.gray)
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Countdown parts

/// Whole days, hours, minutes and seconds until a moment, never negative.
private struct CountdownParts {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(until target: Date, from now: Date) {
        let total = max(0, Int(target.timeIntervalSince(now)))

        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }
}
