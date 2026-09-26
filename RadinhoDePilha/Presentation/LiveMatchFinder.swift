import Foundation
import Observation

/// Looks for a live Náutico match and reports what it found.
///
/// Exists so the "reproduzir partida ao vivo" control can answer a question with three genuinely
/// different answers, there is a match, there is none but here is the next one, or the lookup
/// failed, and so that each answer can be both shown and spoken.
///
/// Speaking the answer is not a nicety. The control is most useful to someone who cannot read the
/// alert, and "nothing happened" is the one outcome the app must never produce.
@MainActor
@Observable
final class LiveMatchFinder {
    /// What a lookup concluded.
    enum Outcome: Equatable {
        /// A match is under way.
        case live(Match)

        /// Nothing under way. Carries the next fixture when the season has one left.
        case idle(next: Match?)

        /// The lookup itself failed.
        case failed(String)
    }

    private(set) var isSearching = false

    /// Last result, or `nil` before the first lookup.
    private(set) var outcome: Outcome?

    private let provider: MatchDataProvider
    private let speech: any SpeechService
    private let dates = SpokenDate()

    /// Team being followed, as the **domain** identifies it.
    ///
    /// A string rather than the vendor's integer: this type belongs to the presentation layer and
    /// has no business knowing how API-Football numbers its clubs. The conversion happens once, at
    /// the default value.
    private let teamID: String

    init(
        provider: MatchDataProvider,
        speech: any SpeechService,
        teamID: String = String(APIFootballMapper.nauticoTeamID)
    ) {
        self.provider = provider
        self.speech = speech
        self.teamID = teamID
    }

    /// Whether the live provider is configured at all.
    ///
    /// Without a credential the control cannot work, and saying so is better than letting someone
    /// press a button that silently does nothing.
    static var isAvailable: Bool { AppConfiguration.hasAPIFootballKey }

    // MARK: - Lookup

    /// Searches, announces the result aloud, and stores it for the interface.
    func search(season: Int = Calendar.current.component(.year, from: Date())) async {
        isSearching = true
        outcome = nil

        do {
            let live = try await provider.liveMatches(competition: .brasileiraoSerieB, season: season)
            let ours = Self.match(for: teamID, in: live)

            if let ours {
                // Not announced here. The caller tears down the current session before starting
                // the live one, which clears the speech queue, so anything said now would be cut
                // off mid-sentence. The narration's own opening names the teams instead, and that
                // is the confirmation the listener hears.
                outcome = .live(ours)
            } else {
                let next = try? await nextFixture()
                outcome = .idle(next: next)
                await speech.speakNow(idleAnnouncement(next: next), priority: .high)
            }
        } catch let error as MatchDataError {
            outcome = .failed(error.userFacingMessage)
            await speech.speakNow(error.userFacingMessage, priority: .high)
        } catch {
            let message = "Não foi possível verificar se há partida agora."
            outcome = .failed(message)
            await speech.speakNow(message, priority: .high)
        }

        isSearching = false
    }

    /// The next scheduled fixture, when the provider can supply one.
    ///
    /// Asks through ``MatchScheduleProvider`` rather than the vendor's concrete type, so this layer
    /// does not know which vendor it is talking to. A provider without a schedule makes the app say
    /// only that there is no match, which is true and sufficient.
    private func nextFixture() async throws -> Match? {
        guard let schedule = provider as? MatchScheduleProvider else { return nil }

        return try await schedule.nextMatch(forTeam: teamID)
    }

    /// The match the followed team is playing, among those in progress.
    ///
    /// Shared with ``MatchdayViewModel``, so both ways of reaching a live match agree on which one
    /// is Náutico's. Checks the status as well as the team: the vendor's live list holds only matches
    /// in progress, but nothing in the contract promises that, and a scheduled match mistaken for a
    /// live one would start a narration with nothing to narrate.
    static func match(for teamID: String, in live: [Match]) -> Match? {
        live.first { $0.isLive && ($0.homeTeam.id == teamID || $0.awayTeam.id == teamID) }
    }

    // MARK: - Wording

    /// Says there is no match, and when the next one is.
    ///
    /// The second half is what makes the answer useful. "Não há partida agora" closes the
    /// conversation; naming the day and time answers the question the listener actually had.
    func idleAnnouncement(next: Match?) -> String {
        let opening = "Não há partida do Náutico pela Série B neste momento."

        guard let next else {
            return "\(opening) Nenhum próximo jogo está agendado."
        }

        let opponent = opponentName(in: next)
        let when = dates.phrase(for: next.kickoff)

        return "\(opening) O próximo jogo é contra o \(opponent), \(when)."
    }

    /// Text for the alert, which can afford symbols the synthesiser cannot.
    func idleMessage(next: Match?) -> String {
        guard let next else {
            return "Não há partida do Náutico pela Série B agora, e nenhum próximo jogo está agendado."
        }

        return """
        Não há partida do Náutico pela Série B agora.

        Próximo jogo: contra o \(opponentName(in: next)), \(dates.compact(for: next.kickoff)).
        """
    }

    private func opponentName(in match: Match) -> String {
        match.homeTeam.id == teamID ? match.awayTeam.shortName : match.homeTeam.shortName
    }
}
