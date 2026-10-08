import Foundation
import Observation

/// Decides what the narration tab shows when it opens: the match in progress, or the countdown to
/// the next one.
///
/// The tab used to open on a recorded 2022 match with no relation to the day, and finding a real
/// match lived behind a button on a screen the code itself calls a development instrument. With a
/// credential configured, the tab now answers the question someone opening it actually has: is
/// Náutico playing, and if not, when.
///
/// ## Speaking
///
/// Nothing is said on opening. The app has never spoken at launch, and opening it may be for any
/// reason. VoiceOver reads the screen for those who use it, and every piece of information here
/// can also be asked for aloud through ``speakTimeRemaining()`` and ``speakLastResult()``.
///
/// Two moments are announced unprompted, because they are events rather than screens: the kick-off
/// time arriving, and the match actually starting.
///
/// ## When the match starts
///
/// Narration starts by itself, introduced by "A partida começou". Someone who has been waiting on
/// the countdown was waiting for exactly this, probably without looking at the phone, and asking
/// them to find a play button at kick-off would defeat the point of waiting in the app.
///
/// Opening the app while a match is already on is different: the screen goes to the match but does
/// not start talking, for the reason above.
@MainActor
@Observable
final class MatchdayViewModel {
    /// What the tab is showing.
    enum Phase: Equatable {
        case loading

        /// A match is in progress. `introduction`, when present, is spoken before narration starts,
        /// and its presence is what asks narration to start by itself.
        case live(Match, introduction: String?)

        /// The next match has not kicked off yet.
        case upcoming(next: Match, last: Match?)

        /// Kick-off time has passed but the provider still reports the match as not started. The
        /// vendor sometimes takes a minute or two to change the status.
        case awaitingKickoff(next: Match, last: Match?)

        /// Nothing scheduled.
        case noUpcoming(last: Match?)

        case failed(String)
    }

    private(set) var phase: Phase = .loading

    private let provider: MatchDataProvider
    private let schedule: MatchScheduleProvider
    private let speech: any SpeechService
    private let dates: SpokenDate

    /// Team being followed, as the domain identifies it.
    private let teamID: String

    /// Source of the current time, injected so tests can put kick-off in the past or the future.
    private let now: @Sendable () -> Date

    /// Gap between checks once kick-off time has passed, until the vendor reports the match started.
    ///
    /// Fifteen seconds, the vendor's refresh interval. This stretch lasts a minute or two, so its
    /// cost is a handful of requests, and checking once a minute instead would start the narration
    /// up to 45 seconds late. The countdown before it makes no requests at all.
    private let kickoffPollInterval: Duration

    /// Longest single sleep while counting down, so the wake-up still lands on time if the clock
    /// changes or the app was suspended in between.
    private let countdownStep: Duration

    private var waitTask: Task<Void, Never>?

    init(
        provider: MatchDataProvider,
        schedule: MatchScheduleProvider,
        speech: any SpeechService,
        teamID: String = String(APIFootballMapper.nauticoTeamID),
        dates: SpokenDate = SpokenDate(),
        now: @escaping @Sendable () -> Date = { Date() },
        kickoffPollInterval: Duration = .seconds(15),
        countdownStep: Duration = .seconds(30)
    ) {
        self.provider = provider
        self.schedule = schedule
        self.speech = speech
        self.teamID = teamID
        self.dates = dates
        self.now = now
        self.kickoffPollInterval = kickoffPollInterval
        self.countdownStep = countdownStep
    }

    // MARK: - Loading

    /// Finds the live match, or the last and next ones.
    ///
    /// Costs three requests at most: the live list, then the last and next fixtures. Nothing more is
    /// requested until kick-off time, however long the countdown.
    func load() async {
        waitTask?.cancel()
        phase = .loading

        do {
            let season = Calendar.current.component(.year, from: now())
            let inProgress = try await provider.liveMatches(competition: .brasileiraoSerieB, season: season)

            if let ours = LiveMatchFinder.match(for: teamID, in: inProgress) {
                phase = .live(ours, introduction: nil)
                return
            }

            // The last result is a courtesy; failing to get it must not hide the next match.
            let last = try? await schedule.lastMatch(forTeam: teamID)
            let next = try await schedule.nextMatch(forTeam: teamID)

            guard let next else {
                phase = .noUpcoming(last: last)
                return
            }

            phase = .upcoming(next: next, last: last)
            waitForKickoff(of: next, last: last)
        } catch let error as MatchDataError {
            phase = .failed(error.userFacingMessage)
        } catch {
            phase = .failed("Não foi possível consultar os jogos do Náutico.")
        }
    }

    /// Stops the countdown and any polling, for when narration takes over.
    func stop() {
        waitTask?.cancel()
        waitTask = nil
    }

    // MARK: - Waiting for kick-off

    private func waitForKickoff(of next: Match, last: Match?) {
        waitTask?.cancel()

        waitTask = Task { [weak self] in
            guard let self else { return }

            // Sleeps in bounded steps rather than once for the whole countdown, so a match days away
            // still wakes on time after the phone has slept or the clock has been adjusted.
            while !Task.isCancelled {
                let remaining = next.kickoff.timeIntervalSince(self.now())
                guard remaining > 0 else { break }

                let step = min(Duration.milliseconds(Int64(remaining * 1000)), self.countdownStep)
                do { try await Task.sleep(for: step) } catch { return }
            }

            guard !Task.isCancelled else { return }
            await self.awaitKickoff(of: next, last: last)
        }
    }

    /// Checks every `kickoffPollInterval` until the provider reports the match under way.
    private func awaitKickoff(of next: Match, last: Match?) async {
        phase = .awaitingKickoff(next: next, last: last)

        await speech.speakNow(
            "Chegou a hora do jogo, \(teams(of: next)). Aguardando o início da partida.",
            priority: .high
        )

        while !Task.isCancelled {
            if let current = try? await provider.match(withID: next.id) {
                if current.isLive {
                    phase = .live(current, introduction: "A partida começou.")
                    return
                }

                if Self.hasEndedWithoutUs(current.status) {
                    // The app slept through it, or it was postponed. Either way this is no longer
                    // the match to wait for; look up whatever is next.
                    await load()
                    return
                }
            }

            do { try await Task.sleep(for: kickoffPollInterval) } catch { return }
        }
    }

    private static func hasEndedWithoutUs(_ status: MatchStatus) -> Bool {
        switch status {
        case .finished, .postponed, .cancelled, .abandoned, .awarded: true
        default: false
        }
    }

    // MARK: - Spoken on request

    /// Answers "quanto falta?" aloud.
    ///
    /// Says the teams and the day as well as the time left, because someone asking without seeing
    /// the screen may not know which match the countdown is for.
    func speakTimeRemaining() async {
        await speech.speakNow(timeRemainingAnnouncement(), priority: .high)
    }

    /// Says the last result aloud.
    func speakLastResult() async {
        await speech.speakNow(lastResultAnnouncement(), priority: .high)
    }

    func timeRemainingAnnouncement() -> String {
        switch phase {
        case .upcoming(let next, _):
            let remaining = dates.remainingSentence(until: next.kickoff, from: now())
            let when = dates.phrase(for: next.kickoff, relativeTo: now())

            return "\(remaining) para \(teams(of: next)), \(when)."
        case .awaitingKickoff(let next, _):
            return "O horário do jogo já chegou. Aguardando o início da partida, \(teams(of: next))."
        case .noUpcoming:
            return "Nenhum próximo jogo do Náutico está agendado."
        case .live(let match, _):
            return "A partida já está em andamento, \(teams(of: match))."
        case .loading:
            return "Consultando os jogos do Náutico."
        case .failed(let message):
            return message
        }
    }

    func lastResultAnnouncement() -> String {
        guard let last = lastMatch else { return "Não há resultado anterior disponível." }

        let day = dates.dayPhrase(for: last.kickoff, relativeTo: now())

        return """
        Último jogo: \(last.homeTeam.shortName) \(last.score.home), \
        \(last.awayTeam.shortName) \(last.score.away), \
        pelo \(last.competition.displayName), \(day).
        """
    }

    // MARK: - Screen text

    /// The countdown as the accessibility label reads it: by the minute, never by the second.
    ///
    /// The visible digits change every second, and a label that did the same would make VoiceOver
    /// either chatter or lag. Minute granularity stays accurate enough to act on.
    func countdownLabel(at date: Date) -> String {
        guard case .upcoming(let next, _) = phase else { return "" }

        let sentence = dates.remainingSentence(until: next.kickoff, from: date)
        return String(sentence.dropLast())  // without the full stop, as a label
    }

    /// The match the screen is about, whichever phase.
    var featuredMatch: Match? {
        switch phase {
        case .upcoming(let next, _), .awaitingKickoff(let next, _): next
        case .live(let match, _): match
        default: nil
        }
    }

    var lastMatch: Match? {
        switch phase {
        case .upcoming(_, let last), .awaitingKickoff(_, let last), .noUpcoming(let last): last
        default: nil
        }
    }

    func kickoffPhrase(for match: Match) -> String {
        dates.compact(for: match.kickoff)
    }

    private func teams(of match: Match) -> String {
        "\(match.homeTeam.shortName) e \(match.awayTeam.shortName)"
    }
}
