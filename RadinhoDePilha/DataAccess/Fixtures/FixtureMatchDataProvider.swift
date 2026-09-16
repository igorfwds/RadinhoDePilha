import Foundation

/// Matches loaded from API-Football responses recorded to disk.
///
/// Recorded payloads serve two purposes the live provider cannot. They make development and tests
/// deterministic and free of quota, the free plan allows a hundred requests a day, which a single
/// polled match would exhaust, and they let the app be demonstrated without waiting for Náutico
/// to be playing, which matters for a dissertation defence scheduled independently of the fixture
/// list.
///
/// The recordings are genuine vendor output, not hand-written JSON. Anything the app can parse
/// here it can parse live, and the quirks the adapter corrects are present in the file.
nonisolated enum RecordedMatches {
    /// Náutico 4×3 Tombense, round 33 of Série B 2022.
    ///
    /// Chosen because a single match exercises nearly every narration path: seven goals including
    /// one from the penalty spot, a VAR review, five bookings, ten substitutions and stoppage time
    /// in both halves.
    static let nauticoTombense = "fixture-838946"

    /// Náutico 1×0 Sport, Pernambucano 2024, at the Estádio Eládio de Barros Carvalho.
    ///
    /// Used to preview the narrator personas. The Clássico dos Clássicos decided by a single goal
    ///, Patrick Allan at 58 minutes, is the most recognisable moment available: it is the only
    /// Náutico win over Sport in the seasons the free plan reaches.
    static let nauticoSport = "fixture-1147708"

    /// Decodes a recorded fixture into the domain.
    ///
    /// - Throws: ``MatchDataError/decoding(underlying:)`` when the resource is missing or
    ///   malformed. Missing is treated as a decoding failure rather than a special case: either
    ///   way the app cannot read data it was built to contain, which is a packaging error rather
    ///   than something a listener can act on.
    static func match(named name: String, in bundle: Bundle = .main) throws -> Match {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw MatchDataError.decoding(underlying: "Recurso \(name).json não encontrado")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            let items = try decoder
                .decode(APIFootballResponse<[APIFootballFixtureItem]>.self, from: data)
                .response

            guard let item = items.first else {
                throw MatchDataError.decoding(underlying: "\(name).json não contém partidas")
            }

            return APIFootballMapper.match(from: item, events: item.events ?? [])
        } catch let error as MatchDataError {
            throw error
        } catch {
            throw MatchDataError.decoding(underlying: error.localizedDescription)
        }
    }
}

/// Provider backed by recorded responses.
///
/// Conforms to the same contract as the live provider, so screens and view models cannot tell the
/// difference, which is the practical test of whether the seam in ADR-001 actually holds.
nonisolated struct FixtureMatchDataProvider: MatchDataProvider {
    private let matches: [Match]

    init(matches: [Match]) {
        self.matches = matches
    }

    /// Loads the recorded matches shipped with the app.
    init(bundle: Bundle = .main, names: [String] = [RecordedMatches.nauticoTombense]) throws {
        matches = try names.map { try RecordedMatches.match(named: $0, in: bundle) }
    }

    func liveMatches(competition: Competition, season: Int) async throws -> [Match] {
        matches.filter { $0.competition == competition && $0.season == season && $0.isLive }
    }

    func match(withID id: String) async throws -> Match {
        guard let match = matches.first(where: { $0.id == id }) else {
            throw MatchDataError.matchNotFound(id: id)
        }

        return match
    }
}
