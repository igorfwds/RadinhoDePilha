import Foundation

/// What a listener is told before a match starts.
///
/// Following a match by ear is easier when the frame is already in place: which competition, who
/// plays whom, who is at home, and when. Said once before kick-off, it spares the live narration
/// from having to establish any of it while the ball is moving.
///
/// Limited on purpose to what the data sources already supply for a fixture. Line-ups and league
/// position would belong here too, and are left out rather than invented: neither is part of the
/// domain yet.
nonisolated struct PreMatchBriefing: Sendable {
    private let dates: SpokenDate

    init(dates: SpokenDate = SpokenDate()) {
        self.dates = dates
    }

    /// The briefing as one spoken passage.
    func text(for match: Match, relativeTo now: Date = Date()) -> String {
        let home = match.homeTeam.shortName
        let away = match.awayTeam.shortName

        return [
            "Pré-jogo.",
            "\(match.competition.displayName).",
            "\(home) e \(away) se enfrentam \(dates.phrase(for: match.kickoff, relativeTo: now)).",
            "Mandante: \(home). Visitante: \(away).",
            closing(for: match.status)
        ]
        .joined(separator: " ")
    }

    /// Says what to expect next, which depends on whether the match has started.
    private func closing(for status: MatchStatus) -> String {
        switch status {
        case .scheduled:
            "A narração começa quando a bola rolar."
        case .postponed:
            "A partida foi adiada."
        case .cancelled:
            "A partida foi cancelada."
        default:
            status.isLive ? "A partida já está em andamento." : "A partida já foi encerrada."
        }
    }
}
