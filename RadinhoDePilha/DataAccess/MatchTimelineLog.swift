import Foundation

/// Three plain-text logs of a match as the app lived it, kept next to the raw snapshots.
///
/// - `comentarios.txt`: each vendor comment, stamped with the moment the app first saw it.
/// - `narracao.txt`: each sentence the app narrated, stamped with the moment it was queued.
/// - `linha-do-tempo.txt`: both together, in the order they were written.
///
/// The raw snapshots say what the vendor knew; these say when each piece reached the listener's
/// side, which is what comparing the commentary feed with the narration needs. One line per
/// entry, tab-separated: time in UTC, source, match minute, kind, text.
///
/// An actor so that comments, arriving from the recorder, and narration, arriving from the
/// screen, are written one at a time and never interleave inside a line.
actor MatchTimelineLog {
    private let directory: URL

    /// Comments already written, per match, so each is logged once.
    private var seenComments: [String: Set<Int>] = [:]

    init(directory: URL = SportmonksRecordings.directory) {
        self.directory = directory
    }

    // MARK: - Narration

    /// Notes a sentence the app is about to speak.
    ///
    /// Callable from anywhere without waiting: the moment is captured here, on the caller's side,
    /// so the time written is when the narration was produced and not when the log got to it.
    nonisolated func narrated(
        _ text: String,
        minute: Int,
        stoppageMinute: Int?,
        kind: String,
        matchID: String,
        at moment: Date = Date()
    ) {
        let label = Self.minuteLabel(minute, stoppageMinute)

        Task {
            await self.write(
                source: "NARRACAO",
                file: "narracao.txt",
                minute: label,
                kind: kind,
                text: text,
                matchID: matchID,
                at: moment
            )
        }
    }

    // MARK: - Comments

    /// Logs the comments in a vendor response that have not been logged before.
    func comments(in response: Data, matchID: String, at moment: Date) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let comments = try? decoder.decode(Envelope.self, from: response).data?.comments else {
            return
        }

        let ordered = comments.sorted { ($0.order ?? 0) < ($1.order ?? 0) }

        if seenComments[matchID] == nil {
            // First response of this session. If a log is already on disk the app was restarted
            // mid-match, and writing everything again would stamp old comments with a new time.
            let resumed = FileManager.default.fileExists(
                atPath: folder(for: matchID).appendingPathComponent("comentarios.txt").path
            )
            seenComments[matchID] = resumed ? Set(ordered.map(\.id)) : []
        }

        for comment in ordered where seenComments[matchID]?.contains(comment.id) == false {
            seenComments[matchID]?.insert(comment.id)

            write(
                source: "COMENTARIO",
                file: "comentarios.txt",
                minute: Self.minuteLabel(comment.minute ?? 0, comment.extraMinute),
                kind: comment.isGoal == true ? "goal" : "",
                text: comment.comment,
                matchID: matchID,
                at: moment
            )
        }
    }

    nonisolated private struct Envelope: Decodable {
        let data: Fixture?
    }

    nonisolated private struct Fixture: Decodable {
        let comments: [Comment]?
    }

    nonisolated private struct Comment: Decodable {
        let id: Int
        let comment: String
        let minute: Int?
        let extraMinute: Int?
        let isGoal: Bool?
        let order: Int?
    }

    // MARK: - Writing

    private static func minuteLabel(_ minute: Int, _ stoppage: Int?) -> String {
        stoppage.map { "\(minute)+\($0)'" } ?? "\(minute)'"
    }

    private func folder(for matchID: String) -> URL {
        directory.appendingPathComponent("sportmonks-\(matchID)", isDirectory: true)
    }

    /// Writes one entry to its own log and to the combined one.
    private func write(
        source: String,
        file: String,
        minute: String,
        kind: String,
        text: String,
        matchID: String,
        at moment: Date
    ) {
        // Tabs and line breaks inside the text would break the one-entry-per-line format.
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let line = [moment.formatted(.iso8601), source, minute, kind, flat].joined(separator: "\t")

        let folder = folder(for: matchID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        append(line, to: folder.appendingPathComponent(file))
        append(line, to: folder.appendingPathComponent("linha-do-tempo.txt"))
    }

    private func append(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)

        guard let handle = try? FileHandle(forWritingTo: url) else {
            // No file yet: this line creates it.
            try? data.write(to: url)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
