import Foundation

/// Live match data from the Sportmonks Football API v3.
///
/// The sibling of ``APIFootballProvider`` that ADR-001 promised would be cheap to write: it
/// conforms to the same contract, returns the same domain vocabulary, and nothing above the data
/// access layer changes because it exists.
///
/// ## One request per cycle
///
/// A fixture requested with `include=participants;scores;periods;events` returns everything a
/// polling cycle needs in a single payload.
///
/// ## Quota
///
/// The vendor counts requests per hour and per entity, and every call made here is against the
/// fixture entity. The free plan allows 180 an hour, measured on a real account, and reaches only
/// the Danish and Scottish top divisions; the paid plans start at 2,000.
nonisolated struct SportmonksProvider: MatchDataProvider {
    private let token: String
    private let session: URLSession
    private let baseURL: URL

    /// Competition this provider follows, fixed for the same reason as in ``APIFootballProvider``.
    private let leagueID: Int

    /// Keeps raw snapshots of the matches being followed, when the case study wants them.
    private let recorder: SportmonksRecorder?

    /// Everything the mapper reads beyond the fixture itself.
    private static let includes = "participants;scores;periods;events"

    /// Gap between polls that suits this vendor.
    ///
    /// Three and a half seconds is about 1,030 requests an hour. The recorder adds its own on
    /// every third poll, about 340 more, so a match costs some 1,370 of the 2,000 an hour the
    /// Starter plan allows per entity. That leaves room for the recording script running on a Mac
    /// with the same token, about 120 an hour, but not for a second phone narrating the same match.
    /// The free plan allows 180, which does not matter in practice: it cannot see Série B at all.
    static let pollInterval = Duration.milliseconds(3500)

    init(
        token: String,
        leagueID: Int = SportmonksMapper.serieBLeagueID,
        recorder: SportmonksRecorder? = nil,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.sportmonks.com/v3/football")!
    ) {
        self.token = token
        self.leagueID = leagueID
        self.recorder = recorder
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - MatchDataProvider

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        // No season: a match in progress belongs to whatever season is current.
        let fixtures: [SportmonksFixture]? = try await get(
            path: "livescores/inplay",
            query: [
                URLQueryItem(name: "include", value: Self.includes),
                URLQueryItem(name: "filters", value: "fixtureLeagues:\(leagueID)")
            ]
        )

        return (fixtures ?? []).map(SportmonksMapper.match(from:))
    }

    func match(withID id: String) async throws -> Match {
        let fixture: SportmonksFixture? = try await get(
            path: "fixtures/\(id)",
            query: [URLQueryItem(name: "include", value: Self.includes)]
        )

        guard let fixture else {
            throw MatchDataError.matchNotFound(id: id)
        }

        let match = SportmonksMapper.match(from: fixture)
        record(match)

        return match
    }

    /// Hands a match being played, or just ended, to the recorder without waiting for it.
    ///
    /// Detached so that a slow recording request never delays the narration that triggered it.
    private func record(_ match: Match) {
        guard let recorder, match.isLive || match.status == .finished else { return }

        let id = match.id
        let isFinal = !match.isLive

        Task.detached(priority: .utility) {
            await recorder.record(fixtureID: id, isFinal: isFinal)
        }
    }

    // MARK: - Scheduling

    /// A team's fixtures between two days, in every competition the subscription reaches.
    ///
    /// Asked of the team rather than of the league, so a state championship or cup match shows up
    /// as the last or next one when that is what it is.
    private func fixtures(ofTeam teamID: Int, from start: Date, to end: Date) async throws -> [Match] {
        let fixtures: [SportmonksFixture]? = try await get(
            path: "fixtures/between/\(Self.day(start))/\(Self.day(end))/\(teamID)",
            query: [
                URLQueryItem(name: "include", value: "participants;scores"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "sortBy", value: "starting_at"),
                URLQueryItem(name: "order", value: "asc")
            ]
        )

        return (fixtures ?? []).map(SportmonksMapper.match(from:))
    }

    /// How far back and ahead the schedule looks. A club plays at least weekly in season, so six
    /// weeks covers any break short of the gap between seasons.
    private static let scheduleWindow: TimeInterval = 45 * 24 * 60 * 60

    /// A date in the `yyyy-MM-dd` form the vendor's range endpoints take, in UTC.
    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    // MARK: - Transport

    private func get<Payload: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> Payload? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query

        guard let url = components?.url else {
            throw MatchDataError.network(underlying: "URL inválida para \(path)")
        }

        var request = URLRequest(url: url)
        // In the header rather than as `api_token` in the query string, so the credential never
        // ends up in a logged URL.
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MatchDataError.network(underlying: error.localizedDescription)
        }

        try check(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(SportmonksResponse<Payload>.self, from: data).data
        } catch {
            throw MatchDataError.decoding(underlying: String(describing: error))
        }
    }

    /// Unlike API-Football, this vendor reports failures through the status code. A bad token is
    /// a 401, confirmed against the live API; the documentation gives 429 for an exhausted hourly
    /// allowance.
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw MatchDataError.unauthorized
        case 429:
            throw MatchDataError.quotaExceeded
        default:
            throw MatchDataError.providerFailure(status: http.statusCode)
        }
    }
}

// MARK: - MatchScheduleProvider

nonisolated extension SportmonksProvider: MatchScheduleProvider {
    /// A domain identifier that is not one of this vendor's numbers cannot name a team here, and is
    /// answered with nothing rather than with an error, as ``APIFootballProvider`` does.
    func lastMatch(forTeam teamID: String) async throws -> Match? {
        guard let vendorID = Int(teamID) else { return nil }

        let now = Date()

        return try await fixtures(ofTeam: vendorID, from: now.addingTimeInterval(-Self.scheduleWindow), to: now)
            .filter { $0.status == .finished }
            .max { $0.kickoff < $1.kickoff }
    }

    /// The earliest fixture not yet started.
    ///
    /// Chosen by status and not by the clock: at kick-off time the vendor still reports the match
    /// as not started for a minute or two, and it has to remain the next match throughout, since
    /// that is the stretch in which the app is waiting for it to begin.
    func nextMatch(forTeam teamID: String) async throws -> Match? {
        guard let vendorID = Int(teamID) else { return nil }

        let now = Date()

        return try await fixtures(ofTeam: vendorID, from: now, to: now.addingTimeInterval(Self.scheduleWindow))
            .filter { $0.status == .scheduled }
            .min { $0.kickoff < $1.kickoff }
    }
}
