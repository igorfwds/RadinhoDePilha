import Foundation

/// Where raw Sportmonks responses are kept on the device, and how much is there.
///
/// The folder sits inside the app's Documents directory, which `Config/Info.plist` exposes to the
/// Files app. That is the whole export mechanism: after a match the recordings are picked up from
/// Files, or from Finder with the phone plugged in, with no export code to maintain.
nonisolated enum SportmonksRecordings {
    /// `Documents/Gravacoes`, one subfolder per match.
    static var directory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gravacoes", isDirectory: true)
    }

    /// How many responses are stored and the space they take.
    nonisolated struct Summary: Hashable, Sendable {
        let count: Int
        let bytes: Int64

        static let empty = Summary(count: 0, bytes: 0)

        /// Space used, the way Files would show it.
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    static func summary(in directory: URL = directory) -> Summary {
        let files = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        var count = 0
        var bytes: Int64 = 0

        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }

            count += 1
            bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        return Summary(count: count, bytes: bytes)
    }
}

/// Saves what the vendor sent during a match, for analysis after the fact.
///
/// The case study needs to know what Sportmonks delivers for a Série B match and when, and that
/// can only be observed while a match is being played. Each snapshot is the vendor's response
/// exactly as received, asked for with more detail than narration uses: commentary, team
/// statistics and per-player totals such as fouls committed and drawn.
///
/// ## Kept out of the narration path
///
/// Recording makes its own requests, on its own schedule, and every failure is swallowed. A
/// recording that cannot be made must never cost the listener a goal, least of all on a mobile
/// connection inside a stadium.
///
/// ## Cost
///
/// A snapshot is taken on practically every poll, about one every ten seconds, so that the
/// moment a comment appears or a player's foul count goes up can be placed to within a poll. Each
/// is about 14 kB over the network, compressed, and about 150 kB on disk: roughly 9 MB of mobile
/// data and 100 MB of storage for a whole match, measured on a finished Série B fixture.
actor SportmonksRecorder {
    private let token: String
    private let session: URLSession
    private let baseURL: URL
    private let directory: URL

    /// Where newly seen comments are written as plain text, when a log is kept.
    private let log: MatchTimelineLog?

    /// Minimum gap between snapshots of the same match.
    ///
    /// Just under the polling interval, so that every poll yields a snapshot without two polls
    /// landing close together yielding two.
    private let interval: TimeInterval

    /// When each match was last attempted, successful or not, so a failing connection is not
    /// retried on every poll.
    private var lastAttempt: [String: Date] = [:]

    /// Matches whose final state is already on disk.
    private var completed: Set<String> = []

    /// Matches with a snapshot request under way.
    ///
    /// An actor lets a second call in while the first waits on the network, so without this two
    /// polls arriving together at full time would each save a closing snapshot.
    private var inFlight: Set<String> = []

    /// Position in ``includeLadder`` that the subscription is known to accept.
    private var includeLevel = 0

    /// What to ask for, richest first.
    ///
    /// The vendor rejects a whole request when the plan does not cover one of its includes, and
    /// which ones a Série B subscription covers is not known in advance. Stepping down keeps
    /// something on disk either way; the last entry is what narration itself asks for, which is
    /// known to work whenever the app is narrating at all.
    static let includeLadder = [
        "participants;scores;periods;events;comments;state;statistics;lineups.details",
        "participants;scores;periods;events;comments;state;statistics;lineups",
        "participants;scores;periods;events"
    ]

    init(
        token: String,
        directory: URL = SportmonksRecordings.directory,
        log: MatchTimelineLog? = nil,
        interval: TimeInterval = 8,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.sportmonks.com/v3/football")!
    ) {
        self.token = token
        self.directory = directory
        self.log = log
        self.interval = interval
        self.session = session
        self.baseURL = baseURL
    }

    /// Takes a snapshot of a match unless one was taken too recently.
    ///
    /// - Parameter isFinal: The match has ended. The closing snapshot carries the full-time
    ///   statistics, so it is taken regardless of the interval, once.
    func record(fixtureID: String, isFinal: Bool, now: Date = Date()) async {
        guard !completed.contains(fixtureID), !inFlight.contains(fixtureID) else { return }

        if !isFinal, let last = lastAttempt[fixtureID], now.timeIntervalSince(last) < interval {
            return
        }

        lastAttempt[fixtureID] = now
        inFlight.insert(fixtureID)
        defer { inFlight.remove(fixtureID) }

        var level = includeLevel

        while level < Self.includeLadder.count {
            switch await fetch(fixtureID: fixtureID, includes: Self.includeLadder[level]) {
            case .received(let data):
                includeLevel = level
                save(data, fixtureID: fixtureID, at: now)
                await log?.comments(in: data, matchID: fixtureID, at: now)
                if isFinal { completed.insert(fixtureID) }
                return

            case .rejected:
                // The plan does not cover something in this request: ask for less.
                level += 1

            case .unreachable:
                // Nothing wrong with the request itself, so the next snapshot tries it again.
                return
            }
        }
    }

    // MARK: - Transport

    nonisolated private enum Outcome {
        case received(Data)
        case rejected
        case unreachable
    }

    private func fetch(fixtureID: String, includes: String) async -> Outcome {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("fixtures/\(fixtureID)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "include", value: includes)]

        guard let url = components?.url else { return .rejected }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }

        switch http.statusCode {
        case 200...299:
            return .received(data)
        case 429, 500...599:
            // Out of quota or the vendor is down: asking for less would not help.
            return .unreachable
        default:
            return .rejected
        }
    }

    // MARK: - Storage

    /// Writes one response to `sportmonks-<id>/<unix time>.json`.
    ///
    /// Named by Unix time so the files sort in the order they were taken and the moment of each
    /// is recoverable without opening it.
    private func save(_ data: Data, fixtureID: String, at moment: Date) {
        let folder = directory.appendingPathComponent("sportmonks-\(fixtureID)", isDirectory: true)
        let file = folder.appendingPathComponent("\(Int(moment.timeIntervalSince1970)).json")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
