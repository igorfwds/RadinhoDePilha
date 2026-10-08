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

    /// Recognises the team being followed.
    ///
    /// A question put to the vendor's side rather than an identifier held here: this type belongs
    /// to the presentation layer and has no business knowing how any vendor numbers its clubs, or
    /// whether it recognises them by number at all.
    private let follows: @Sendable (Team) -> Bool

    /// Looks up the followed team's next fixture, when the provider can supply one.
    private let nextFixtureLookup: (@Sendable () async throws -> Match?)?

    /// Follows the club through a configured live vendor.
    init(source: LiveDataSource, speech: any SpeechService) {
        self.provider = source.provider
        self.speech = speech
        self.follows = source.follows
        self.nextFixtureLookup = source.nextFixture
    }

    /// Follows a team by its domain identifier, against any provider.
    ///
    /// Without a next-fixture lookup, since that is outside ``MatchDataProvider``: the app simply
    /// says there is no match, which is true and sufficient.
    init(provider: MatchDataProvider, speech: any SpeechService, teamID: String) {
        self.provider = provider
        self.speech = speech
        self.follows = { $0.id == teamID }
        self.nextFixtureLookup = nil
    }

    /// Whether a live provider is configured at all.
    ///
    /// Without a credential the control cannot work, and saying so is better than letting someone
    /// press a button that silently does nothing.
    static var isAvailable: Bool { LiveDataSource.configured != nil }

    // MARK: - Lookup

    /// Searches, announces the result aloud, and stores it for the interface.
    func search(season: Int = Calendar.current.component(.year, from: Date())) async {
        isSearching = true
        outcome = nil

        do {
            let live = try await provider.liveMatches(competition: .brasileiraoSerieB, season: season)
            let ours = live.first { follows($0.homeTeam) || follows($0.awayTeam) }

            if let ours {
                outcome = .live(ours)
                await speech.speakNow(liveAnnouncement(for: ours), priority: .high)
            } else {
                let next = try? await nextFixtureLookup?()
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

    // MARK: - Wording

    private func liveAnnouncement(for match: Match) -> String {
        """
        Partida em andamento: \(match.homeTeam.shortName) e \(match.awayTeam.shortName). \
        Começando a narração.
        """
    }

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
        follows(match.homeTeam) ? match.awayTeam.shortName : match.homeTeam.shortName
    }
}
