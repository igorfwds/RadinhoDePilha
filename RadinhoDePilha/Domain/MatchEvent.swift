import Foundation

/// Category of a match occurrence.
///
/// The list covers what is worth narrating and what a listener can tell apart. Anything the
/// provider reports outside this list falls into ``unknown``, which the narration engine
/// skips rather than turning into a meaningless sentence.
nonisolated enum MatchEventKind: String, Hashable, Sendable, CaseIterable {
    case goal
    case ownGoal
    case penaltyScored
    case penaltyMissed
    case yellowCard
    case secondYellowCard
    case redCard
    case substitution
    case varDecision
    case periodStart
    case periodEnd

    /// A corner kick awarded to ``MatchEvent/team``.
    case corner

    /// A foul committed by ``MatchEvent/team``. The player is who committed it and the related
    /// player who suffered it, when either is known.
    case foul

    /// An offside given against ``MatchEvent/team``.
    case offside

    /// Who committed and who suffered a foul already announced without names.
    ///
    /// A separate occurrence rather than an update to the foul, because that is how it reaches
    /// the listener: the foul is said at once, and the names a little later, when the vendor's
    /// player totals catch up with its team totals.
    case foulAttribution

    /// Who was caught offside, for an offside already announced without a name.
    case offsideAttribution

    case unknown
}

/// A single occurrence within a match.
nonisolated struct MatchEvent: Identifiable, Hashable, Sendable {
    let kind: MatchEventKind

    /// Regulation minute. For "45+2", this is 45.
    let minute: Int

    /// Stoppage-time minute, when present. For "45+2", this is 2.
    let stoppageMinute: Int?

    /// Team the occurrence belongs to.
    let team: Team

    /// Main actor of the occurrence: who scored, who was booked, who came on.
    let player: String?

    /// Second party involved: who assisted, or who came off in a substitution.
    let relatedPlayer: String?

    /// Raw provider detail, kept for diagnostics and for ``unknown`` cases.
    let detail: String?

    /// Ordinal among occurrences of the same kind for the same team, when the event was worked
    /// out from a running total instead of being reported individually.
    ///
    /// Two corners for the same side in the same minute are otherwise indistinguishable, and
    /// would share an identifier: the second would never be narrated. The total after the
    /// occurrence tells them apart and stays the same on every later request.
    var sequence: Int? = nil

    /// Identifier derived from the fields that make the occurrence unique within a match.
    ///
    /// Computed rather than stored because providers typically deliver events as a plain
    /// array with no identifier of their own. Generating a `UUID()` during mapping would be
    /// fatal: every polling request would produce fresh identifiers, everything would look
    /// new, and the app would narrate the same goal on every cycle. Deriving from the fields
    /// guarantees a stable id for the same occurrence, which is the premise event diffing
    /// depends on.
    var id: String {
        [
            String(minute),
            stoppageMinute.map(String.init) ?? "0",
            kind.rawValue,
            team.id,
            player ?? "-"
        ]
        .joined(separator: "|") + (sequence.map { "|#\($0)" } ?? "")
    }

    /// Absolute minute, for chronological ordering including stoppage time.
    var absoluteMinute: Int {
        minute + (stoppageMinute ?? 0)
    }
}
