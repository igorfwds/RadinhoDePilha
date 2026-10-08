import Foundation

/// A live vendor, with the few things about it that differ from one vendor to the next.
///
/// ``MatchDataProvider`` and ``MatchScheduleProvider`` cover what every vendor does the same way.
/// This covers what they do differently and the rest of the app still has to know: how often to
/// ask, and what number the vendor gives the club the app follows. Gathering them here keeps the
/// choice of vendor in one expression, ``configured``, instead of repeating it wherever live data
/// is used.
nonisolated struct LiveDataSource: Sendable {
    let provider: any MatchDataProvider

    /// The same vendor, asked about fixtures rather than about a match in progress.
    let schedule: any MatchScheduleProvider

    /// Gap between polls while narrating, as far as the vendor's quota allows.
    let pollInterval: Duration

    /// The followed club, Náutico, as this vendor numbers it.
    let teamID: String

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
            schedule: provider,
            pollInterval: SportmonksProvider.pollInterval,
            teamID: String(SportmonksMapper.nauticoTeamID),
            log: log
        )
    }

    static func apiFootball(key: String) -> LiveDataSource {
        let provider = APIFootballProvider(apiKey: key)

        return LiveDataSource(
            provider: provider,
            schedule: provider,
            // The vendor refreshes its data at most every fifteen seconds, so polling faster adds
            // no detail; it only notices a change sooner. Five seconds keeps a whole match at some
            // 1,560 requests, inside the Pro plan's 7,500 a day, and far from its 300 a minute.
            pollInterval: .seconds(5),
            teamID: String(APIFootballMapper.nauticoTeamID)
        )
    }
}
