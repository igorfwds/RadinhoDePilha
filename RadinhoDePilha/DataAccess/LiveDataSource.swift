import Foundation

/// A live vendor, with the few things about it that differ from one vendor to the next.
///
/// ``MatchDataProvider`` covers what every provider does the same way. This covers what they do
/// differently and the rest of the app still has to know: how often to ask, how to recognise the
/// followed club among the vendor's teams, and how to find that club's next fixture. Gathering
/// them here keeps the choice of vendor in one expression, ``configured``, instead of repeating it
/// wherever a live provider is built.
nonisolated struct LiveDataSource: Sendable {
    let provider: any MatchDataProvider

    /// Gap between polls that the vendor's quota allows.
    let pollInterval: Duration

    /// Whether a team, as this vendor identifies it, is the club the app follows.
    let follows: @Sendable (Team) -> Bool

    /// The followed club's next fixture, or `nil` when none is scheduled.
    let nextFixture: @Sendable () async throws -> Match?

    /// Where the narration of a live match is written down, when this vendor is being recorded.
    var log: MatchTimelineLog?

    /// The vendor the build is configured for, or `nil` without any credential.
    ///
    /// Sportmonks wins when both credentials are present, because it is the vendor under
    /// evaluation. Leaving `SPORTMONKS_TOKEN` empty in `Secrets.xcconfig` hands the app back to
    /// API-Football.
    static var configured: LiveDataSource? {
        if let token = AppConfiguration.sportmonksToken {
            return sportmonks(token: token)
        }

        if let key = AppConfiguration.apiFootballKey {
            return apiFootball(key: key)
        }

        return nil
    }

    static func sportmonks(token: String) -> LiveDataSource {
        // Recording is on for as long as this vendor is under evaluation: what it delivers
        // during a Série B match is the evidence the case study is built on.
        let log = MatchTimelineLog()
        let provider = SportmonksProvider(
            token: token,
            recorder: SportmonksRecorder(token: token, log: log)
        )

        return LiveDataSource(
            provider: provider,
            pollInterval: SportmonksProvider.pollInterval,
            follows: SportmonksMapper.isNautico,
            nextFixture: { try await provider.nextFixture(where: SportmonksMapper.isNautico) },
            log: log
        )
    }

    static func apiFootball(key: String) -> LiveDataSource {
        let provider = APIFootballProvider(apiKey: key)
        let teamID = APIFootballMapper.nauticoTeamID

        return LiveDataSource(
            provider: provider,
            // The vendor's guidance of one call a minute: faster is beyond what the plan allows,
            // and exceeding it can get the account blocked.
            pollInterval: .seconds(60),
            follows: { $0.id == String(teamID) },
            nextFixture: { try await provider.nextFixture(forTeam: teamID) }
        )
    }
}

/// Serves recorded matches from memory and everything else from a live vendor.
///
/// Exists because the narration screen opens on a recorded match, whose identifier belongs to the
/// vendor it was recorded from. Asking a different vendor for that number would fetch an unrelated
/// fixture or none at all, so the recording is answered locally and only matches found live reach
/// the network.
nonisolated struct RecordedFirstProvider: MatchDataProvider {
    let recorded: [Match]
    let live: any MatchDataProvider

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        try await live.liveMatches(competition: competition, season: season)
    }

    func match(withID id: String) async throws -> Match {
        if let match = recorded.first(where: { $0.id == id }) {
            return match
        }

        return try await live.match(withID: id)
    }
}
