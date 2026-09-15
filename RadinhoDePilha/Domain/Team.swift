import Foundation

/// A football club taking part in a match.
///
/// The identifier is a `String` rather than an `Int` because data providers disagree on the
/// format: API-Football uses integers, others use strings or hashes. Keeping `String` in the
/// domain means switching providers costs one conversion in the adapter instead of a change
/// to the domain and to everything that consumes it.
nonisolated struct Team: Identifiable, Hashable, Sendable {
    /// Stable identifier coming from the data source. Never generated locally: event
    /// diffing relies on the same team keeping the same id across requests.
    let id: String

    /// Full name, for on-screen display. E.g. "Clube Náutico Capibaribe".
    let name: String

    /// Short name, for narration. E.g. "Náutico".
    ///
    /// The distinction exists because "Náutico marca" sounds like radio commentary while the
    /// full name does not.
    let shortName: String

    /// Supporters' nickname, when the club has a well-established one. E.g. "Timbu".
    ///
    /// Radio commentary alternates freely between the club name and its nickname, and that
    /// alternation is part of what makes the register recognisable. Optional because most clubs
    /// have no nickname the audience would recognise, and inventing one would sound wrong.
    let nickname: String?

    /// Club crest. Optional because it is not essential to the target audience and may be
    /// missing from the provider response.
    let crestURL: URL?

    /// Names the club may be referred to by, in descending order of formality.
    ///
    /// Used to vary how a side is mentioned across a long broadcast without repeating one form.
    var spokenNames: [String] {
        [shortName, nickname].compactMap(\.self)
    }
}
