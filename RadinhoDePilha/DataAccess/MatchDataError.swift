import Foundation

/// Failure modes any match data provider may report.
///
/// Declared in the data access layer, in vendor-neutral terms, so that view models can react
/// to a failure without knowing which provider produced it. `underlying` carries a
/// description rather than the original `Error` to keep the type `Equatable` and `Sendable`,
/// which makes error paths straightforward to assert in tests.
nonisolated enum MatchDataError: Error, Hashable, Sendable {
    /// The request never completed: no connectivity, timeout, DNS failure.
    case network(underlying: String)

    /// The response arrived but did not match the expected shape.
    ///
    /// Worth surfacing distinctly from ``network(underlying:)``: this one usually means the
    /// vendor changed its payload, not that the user is offline.
    case decoding(underlying: String)

    /// The requested match does not exist, or is no longer available from the provider.
    case matchNotFound(id: String)

    /// The provider rejected the request for lack of credentials.
    case unauthorized

    /// The request quota was exhausted.
    ///
    /// A first-class case because the free API-Football plan allows a limited number of daily
    /// requests, and a live match polled every thirty seconds consumes that budget quickly.
    /// The app has to degrade gracefully instead of failing silently mid-match.
    case quotaExceeded

    /// The provider is reachable but reported an internal failure.
    case providerFailure(status: Int)
}

nonisolated extension MatchDataError {
    /// Message intended for the end user, in Brazilian Portuguese.
    ///
    /// Kept short and free of jargon: it may be read aloud by VoiceOver or by the app's own
    /// speech synthesiser, so it has to make sense as spoken audio.
    var userFacingMessage: String {
        switch self {
        case .network:
            "Não foi possível conectar. Verifique sua internet."
        case .decoding:
            "Os dados da partida chegaram em um formato inesperado."
        case .matchNotFound:
            "Essa partida não está mais disponível."
        case .unauthorized:
            "O acesso aos dados da partida foi recusado."
        case .quotaExceeded:
            "O limite de consultas do dia foi atingido."
        case .providerFailure:
            "O serviço de dados está indisponível no momento."
        }
    }
}
