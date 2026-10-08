import Foundation

/// Wire format of Sportmonks Football API v3 responses.
///
/// These types exist only to decode what the vendor sends, and only the fields the app reads.
/// Property names follow the vendor's snake case through `convertFromSnakeCase`, so
/// `starting_at_timestamp` arrives as `startingAtTimestamp`. Translation is ``SportmonksMapper``'s
/// job.
///
/// Nothing above ``MatchDataProvider`` should ever see one of these.

// MARK: - Envelope

/// Every v3 endpoint wraps its payload in `data`.
nonisolated struct SportmonksResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    /// Absent, or an empty array, when nothing matched.
    ///
    /// The vendor answers HTTP 200 with only a `message` both when the thing does not exist and
    /// when the subscription does not reach it, and the two cannot be told apart from the
    /// response. Optional so that either reads as "nothing here" rather than as a decoding failure.
    let data: Payload?
}

// MARK: - Fixtures

nonisolated struct SportmonksFixture: Decodable, Sendable {
    let id: Int
    let leagueId: Int

    /// Numeric state, see ``SportmonksMapper/status(fromStateID:)``.
    ///
    /// Present on every fixture without asking for the `state` include, which is why the mapper
    /// works from the number rather than from the state's name.
    let stateId: Int

    /// Kick-off as a Unix timestamp.
    ///
    /// Preferred over `starting_at`, a string in the account's configured timezone with no offset
    /// in it: the timestamp means the same instant whatever the account settings say.
    let startingAtTimestamp: Int

    // The four below arrive only when requested through `include`.
    let participants: [SportmonksParticipant]?
    let scores: [SportmonksScore]?
    let periods: [SportmonksPeriod]?
    let events: [SportmonksEvent]?
}

/// A team taking part in a fixture.
nonisolated struct SportmonksParticipant: Decodable, Sendable {
    let id: Int
    let name: String
    let meta: Meta?

    nonisolated struct Meta: Decodable, Sendable {
        /// `home` or `away`. The array order does not say which: real responses list the away
        /// side first.
        let location: String?
    }
}

/// One line of the score breakdown.
nonisolated struct SportmonksScore: Decodable, Sendable {
    /// Which tally this is: `1ST_HALF`, `2ND_HALF`, `CURRENT`…
    let description: String
    let score: Value

    nonisolated struct Value: Decodable, Sendable {
        let goals: Int

        /// `home` or `away`.
        let participant: String
    }
}

/// A half, or a period of extra time, with the vendor's own clock.
nonisolated struct SportmonksPeriod: Decodable, Sendable {
    let sortOrder: Int?

    /// Whether this period is the one being played right now.
    let ticking: Bool?

    /// Match minute the period starts counting from: 0 for the first half, 45 for the second.
    let countsFrom: Int?
    let periodLength: Int?

    /// Running minute, stoppage included: 47 two minutes into first-half stoppage.
    let minutes: Int?
}

// MARK: - Events

nonisolated struct SportmonksEvent: Decodable, Sendable {
    /// Numeric type, see ``SportmonksMapper/kind(fromTypeID:)``.
    let typeId: Int
    let participantId: Int?

    /// Main actor. For a substitution this is the player coming **on**, checked against the
    /// line-ups of real matches, which is already what ``MatchEvent`` expects.
    let playerName: String?
    let relatedPlayerName: String?

    let minute: Int?

    /// Stoppage minutes. For "45+2" this is 2.
    let extraMinute: Int?

    /// Free-text qualifiers: `Right foot shot`, `Foul`, `Goal disallowed`, `1st Goal`…
    let info: String?
    let addition: String?

    /// Vendor's own ordering within the match.
    let sortOrder: Int?

    /// Set when a card was later withdrawn. `false` on cards, null on everything else.
    let rescinded: Bool?
}
