import Foundation

/// Wire format of API-Football v3 responses.
///
/// These types exist only to decode what the vendor sends. They deliberately keep the vendor's
/// own names and shapes, `assist`, `elapsed`, `short`, so that the awkwardness stays contained
/// here instead of leaking into the domain. Translation is ``APIFootballMapper``'s job.
///
/// Nothing above ``MatchDataProvider`` should ever see one of these.

// MARK: - Envelope

/// Every v3 endpoint returns the same envelope around its payload.
nonisolated struct APIFootballResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    let response: Payload

    /// Errors arrive here with HTTP 200, not as a failure status code.
    ///
    /// Worse, the field changes type: an empty array when all is well, an object keyed by reason
    /// when something is wrong. Decoding it as either is why ``APIFootballErrors`` exists.
    let errors: APIFootballErrors
    let results: Int
}

/// The `errors` field, which the vendor types as `[]` when empty and as an object otherwise.
nonisolated struct APIFootballErrors: Decodable, Sendable {
    let messages: [String: String]

    var isEmpty: Bool { messages.isEmpty }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let dictionary = try? container.decode([String: String].self) {
            messages = dictionary
        } else {
            // An array here always means "no errors"; the vendor never populates it.
            messages = [:]
        }
    }

    /// Whether the plan blocks the requested season, which reads as an error rather than as an
    /// empty result.
    var planRestriction: String? { messages["plan"] }
}

// MARK: - Fixtures

nonisolated struct APIFootballFixtureItem: Decodable, Sendable {
    let fixture: APIFootballFixture
    let league: APIFootballLeague
    let teams: APIFootballTeams
    let goals: APIFootballGoals

    /// Present when the fixture was requested by `id` or through `live`, absent when it came in
    /// a season listing.
    ///
    /// This is what makes one request per polling cycle enough: asking for a single fixture
    /// returns its events in the same payload, so there is no second call to `fixtures/events`.
    let events: [APIFootballEvent]?
}

nonisolated struct APIFootballFixture: Decodable, Sendable {
    let id: Int
    let date: Date
    let status: APIFootballStatus
}

nonisolated struct APIFootballStatus: Decodable, Sendable {
    /// Two-letter code: `NS`, `1H`, `HT`, `2H`, `ET`, `P`, `FT`, `AET`, `PEN`, `PST`, `CANC`…
    let short: String

    /// Minutes played, absent before kick-off.
    let elapsed: Int?
}

nonisolated struct APIFootballLeague: Decodable, Sendable {
    let id: Int
    let name: String
    let season: Int
}

nonisolated struct APIFootballTeams: Decodable, Sendable {
    let home: APIFootballTeam
    let away: APIFootballTeam
}

nonisolated struct APIFootballTeam: Decodable, Sendable {
    let id: Int
    let name: String
}

/// Wrapper used by the `teams` endpoint, which nests the club under a `team` key.
nonisolated struct APIFootballTeamItem: Decodable, Sendable {
    let team: APIFootballTeam
}

nonisolated struct APIFootballGoals: Decodable, Sendable {
    /// Null before kick-off, which is not the same as zero.
    let home: Int?
    let away: Int?
}

// MARK: - Events

nonisolated struct APIFootballEvent: Decodable, Sendable {
    let time: APIFootballEventTime
    let team: APIFootballTeam
    let player: APIFootballPerson
    let assist: APIFootballPerson

    /// `Goal`, `Card`, `subst`, `Var`.
    ///
    /// Case is not consistent in practice: the documentation says `Subst` and the API sends
    /// `subst`. Comparisons must be case-insensitive.
    let type: String

    /// Qualifier within the type: `Normal Goal`, `Own Goal`, `Penalty`, `Missed Penalty`,
    /// `Yellow Card`, `Red Card`, `Substitution 1`, `Penalty awarded`…
    ///
    /// The documented list is incomplete, `Penalty awarded` appears in real responses but not in
    /// the docs, so mapping treats unrecognised details as a fallback rather than an error.
    let detail: String
}

nonisolated struct APIFootballEventTime: Decodable, Sendable {
    let elapsed: Int

    /// Stoppage minutes. For "45+2" this is 2.
    let extra: Int?
}

/// A player or coach, either of which may be absent from an event.
nonisolated struct APIFootballPerson: Decodable, Sendable {
    let name: String?
}
