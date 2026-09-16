import AVFoundation
import Foundation

/// A synthesiser voice installed on this device, described for a listener.
nonisolated struct InstalledVoice: Identifiable, Hashable, Sendable {
    /// Platform voice identifier, stable across launches and safe to persist.
    let id: String

    let name: String

    /// Quality tier, which the settings screen states plainly because it is the difference
    /// between a voice that is pleasant for ninety minutes and one that is not.
    let quality: Quality

    nonisolated enum Quality: Int, Comparable, Hashable, Sendable {
        case compact
        case enhanced
        case premium

        var displayName: String {
            switch self {
            case .compact: "Compacta"
            case .enhanced: "Aprimorada"
            case .premium: "Premium"
            }
        }

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Label combining name and quality, for display and for VoiceOver.
    var displayName: String { "\(name) — \(quality.displayName)" }
}

/// The voices this device can narrate with.
///
/// Exists because voice choice cannot be decided at build time: the compact voices ship with the
/// system, while the enhanced and premium ones are downloads the user controls in Settings. The
/// app has to work with whatever is present and let the listener pick among it.
///
/// The distinction is not cosmetic for this project. A compact voice speaking continuously for
/// ninety minutes is markedly harder to listen to, and a participant in an accessibility
/// evaluation may well attribute that fatigue to the narration rather than to the voice — which
/// would contaminate the finding.
nonisolated enum VoiceCatalog {
    static let language = "pt-BR"

    /// Installed voices for the narration language, best quality first.
    static func available(language: String = language) -> [InstalledVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .map {
                InstalledVoice(id: $0.identifier, name: $0.name, quality: quality(of: $0.quality))
            }
            .sorted {
                $0.quality != $1.quality ? $0.quality > $1.quality : $0.name < $1.name
            }
    }

    /// Voice to use when the listener has not chosen one.
    static func preferred(language: String = language) -> InstalledVoice? {
        available(language: language).first
    }

    /// Whether any voice better than compact is installed.
    ///
    /// Drives the hint in the settings screen that points at the system download, so the listener
    /// learns a better voice exists instead of assuming this is as good as it gets.
    static func hasHighQualityVoice(language: String = language) -> Bool {
        available(language: language).contains { $0.quality > .compact }
    }

    private static func quality(of quality: AVSpeechSynthesisVoiceQuality) -> InstalledVoice.Quality {
        switch quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .compact
        }
    }
}
