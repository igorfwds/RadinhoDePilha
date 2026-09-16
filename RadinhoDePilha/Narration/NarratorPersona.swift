import Foundation

/// A narrating voice, in the sense of style rather than synthesiser.
///
/// The project's objectives commit to configurable narrator personas, and this is the type that
/// makes them a first-class choice instead of a hidden constant. The distinction matters for the
/// dissertation: ``SpeechRate`` and the installed system voice change *how the words sound*, while
/// a persona changes *which words are said*.
///
/// Kept in the narration layer, not in the interface, because ``RadioPhrasebook`` is what varies
/// and the engine's match logic must stay identical across personas. That is what allows the same
/// events to be narrated three ways and compared under the same tests.
nonisolated enum NarratorPersona: String, CaseIterable, Hashable, Sendable, Codable {
    /// Measured radio commentary. The register the phrasebook was originally written in.
    case classic

    /// The supporter in the stands: louder, shorter, more exclamation.
    case passionate

    /// Sober and descriptive, closer to a match report read aloud.
    case analytical

    /// Name shown in the settings screen, in Brazilian Portuguese.
    var displayName: String {
        switch self {
        case .classic: "Clássico"
        case .passionate: "Torcedor"
        case .analytical: "Analítico"
        }
    }

    /// One line describing the style, for the settings screen and for VoiceOver.
    ///
    /// Written to be heard: someone choosing a persona without seeing the screen needs to know
    /// what they are picking before they pick it.
    var summary: String {
        switch self {
        case .classic:
            "Narração de rádio equilibrada, como a transmissão tradicional."
        case .passionate:
            "Mais vibrante e exclamativa, como quem está na torcida."
        case .analytical:
            "Mais sóbria e descritiva, com menos emoção e mais detalhe."
        }
    }

    /// Example sentence, so the choice can be previewed before it is applied.
    var sample: String {
        switch self {
        case .classic:
            "É gol do Náutico! Marquinhos empata o jogo."
        case .passionate:
            "Gooool do Náutico! Marquinhos deixa tudo igual!"
        case .analytical:
            "Gol do Náutico, marcado por Marquinhos. O placar está empatado."
        }
    }
}
