import Foundation

/// Live match data from API-Football v3.
///
/// The only type in the app that performs network I/O, and the only one that knows the vendor
/// exists. Everything it returns is domain vocabulary, so swapping vendors means writing a
/// sibling of this file and changing one line in the composition root, the promise of ADR-001.
///
/// ## One request per cycle
///
/// `fixtures?id=` returns the fixture *and* its events in a single payload, so following a live
/// match costs one request per poll rather than two. That halving matters: the free plan allows
/// 100 requests a day, and the vendor recommends polling once a minute while a match is in
/// progress, which is already more than a single match can afford.
nonisolated struct APIFootballProvider: MatchDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    /// Competition this provider follows.
    ///
    /// Fixed rather than derived per call because the app follows one competition, and passing
    /// the vendor's league identifier around would leak it into layers that must not know it.
    private let leagueID: Int

    init(
        apiKey: String,
        leagueID: Int = APIFootballMapper.serieBLeagueID,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://v3.football.api-sports.io")!
    ) {
        self.apiKey = apiKey
        self.leagueID = leagueID
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - MatchDataProvider

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        // `live` accepts only `all` or a dash-separated list of two or more league identifiers:
        // a lone `72` is rejected with a validation error inside a 200 response, which surfaced
        // on match day. `all` narrowed by `league` is the accepted spelling of "this league only".
        // No season either: a match in progress belongs to whatever season is current.
        let items: [APIFootballFixtureItem] = try await get(
            path: "fixtures",
            query: [
                URLQueryItem(name: "live", value: "all"),
                URLQueryItem(name: "league", value: String(leagueID))
            ]
        )

        return items.map { item in
            APIFootballMapper.match(from: item, events: item.events ?? [])
        }
    }

    func match(withID id: String) async throws -> Match {
        let items: [APIFootballFixtureItem] = try await get(
            path: "fixtures",
            query: [URLQueryItem(name: "id", value: id)]
        )

        guard let item = items.first else {
            throw MatchDataError.matchNotFound(id: id)
        }

        return APIFootballMapper.match(from: item, events: item.events ?? [])
    }

    // MARK: - Scheduling

    /// The next fixture for a team that has not kicked off yet.
    ///
    /// Beyond ``MatchDataProvider`` because it answers a question only this app asks: what to say
    /// when there is no match under way. Returning `nil` is a normal outcome, the season ends,
    /// and there is genuinely nothing next.
    func nextFixture(forTeam teamID: Int) async throws -> Match? {
        let items: [APIFootballFixtureItem] = try await get(
            path: "fixtures",
            query: [
                URLQueryItem(name: "team", value: String(teamID)),
                URLQueryItem(name: "next", value: "1")
            ]
        )

        return items.first.map { APIFootballMapper.match(from: $0) }
    }

    // MARK: - Transport

    private func get<Payload: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> Payload {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query

        guard let url = components?.url else {
            throw MatchDataError.network(underlying: "URL inválida para \(path)")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MatchDataError.network(underlying: error.localizedDescription)
        }

        try check(response)

        return try decode(data)
    }

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

    private func decode<Payload: Decodable & Sendable>(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: APIFootballResponse<Payload>

        do {
            envelope = try decoder.decode(APIFootballResponse<Payload>.self, from: data)
        } catch {
            throw MatchDataError.decoding(underlying: error.localizedDescription)
        }

        // The vendor reports failures inside a 200 response rather than through a status code,
        // so this check cannot be skipped just because the request "succeeded".
        try check(envelope.errors)

        return envelope.response
    }

    private func check(_ errors: APIFootballErrors) throws {
        guard !errors.isEmpty else { return }

        if errors.planRestriction != nil {
            // Asking the free plan for a season it does not cover lands here. It is not a quota
            // problem and not a missing match: the data exists, the subscription does not reach
            // it, and saying so plainly is what lets the interface explain itself.
            throw MatchDataError.unauthorized
        }

        // A missing or invalid key also arrives with HTTP 200, under `token`. Reading it as a
        // provider outage would tell the listener the service is down when the fix is local.
        if errors.messages["token"] != nil {
            throw MatchDataError.unauthorized
        }

        // `requests` is the daily allowance, `rateLimit` the per-minute one.
        if errors.messages.keys.contains(where: {
            $0.localizedCaseInsensitiveContains("requests") || $0 == "rateLimit"
        }) {
            throw MatchDataError.quotaExceeded
        }

        throw MatchDataError.providerFailure(status: 200)
    }
}
