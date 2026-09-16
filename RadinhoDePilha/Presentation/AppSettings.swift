import Foundation
import Observation
import SwiftUI

/// How large the interface text should be.
///
/// Offered as an in-app control even though iOS already provides Dynamic Type system-wide,
/// because the two serve different needs. A listener may keep the system at a moderate size for
/// every other app and still want this one large, since it is the app they use while their
/// attention is on a match rather than on the screen.
///
/// ``system`` is the default on purpose: overriding the platform setting by default would ignore a
/// choice the user has already made deliberately.
nonisolated enum TextSizePreference: String, CaseIterable, Hashable, Sendable, Codable {
    case system
    case large
    case extraLarge
    case accessibility

    var displayName: String {
        switch self {
        case .system: "Seguir o sistema"
        case .large: "Grande"
        case .extraLarge: "Muito grande"
        case .accessibility: "Máximo"
        }
    }

    /// Size to force, or `nil` to leave the system's choice alone.
    @MainActor
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .large: .xLarge
        case .extraLarge: .xxxLarge
        case .accessibility: .accessibility3
        }
    }
}

/// Choices the listener has made, kept across launches.
///
/// Isolated to the main actor because it drives the interface directly. Persistence goes through
/// `UserDefaults` rather than SwiftData: these are a handful of scalar preferences, and a database
/// would add a migration surface for no benefit.
///
/// Writing on every change is deliberate. Someone who adjusts the voice mid-match and closes the
/// app should not lose the adjustment, and there is no natural "save" moment in an app that is
/// meant to be listened to rather than operated.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var persona: NarratorPersona {
        didSet { persist(persona.rawValue, forKey: Keys.persona) }
    }

    var rate: SpeechRate {
        didSet { persist(rate.rawValue, forKey: Keys.rate) }
    }

    /// Chosen voice, or `nil` to let the app pick the best installed.
    var voiceIdentifier: String? {
        didSet { persist(voiceIdentifier, forKey: Keys.voice) }
    }

    var textSize: TextSizePreference {
        didSet { persist(textSize.rawValue, forKey: Keys.textSize) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        persona = defaults.string(forKey: Keys.persona)
            .flatMap(NarratorPersona.init(rawValue:)) ?? .classic
        rate = defaults.string(forKey: Keys.rate)
            .flatMap(SpeechRate.init(rawValue:)) ?? .normal
        textSize = defaults.string(forKey: Keys.textSize)
            .flatMap(TextSizePreference.init(rawValue:)) ?? .system
        voiceIdentifier = defaults.string(forKey: Keys.voice)
    }

    /// The voice in use, resolved against a list of installed voices.
    ///
    /// Takes the list as an argument instead of querying the catalogue itself. Reading the
    /// catalogue means asking the system for every installed voice, 180 of them on a typical
    /// device, and this value is consulted once per row while a list renders. Doing that lookup
    /// here made the settings screen visibly stutter.
    ///
    /// Resolving against what is installed still matters: a stored identifier goes stale when the
    /// listener deletes the voice download in system settings.
    func resolvedVoice(among installed: [InstalledVoice]) -> InstalledVoice? {
        if let voiceIdentifier, let match = installed.first(where: { $0.id == voiceIdentifier }) {
            return match
        }

        return installed.first
    }

    private func persist(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let persona = "settings.persona"
        static let rate = "settings.rate"
        static let voice = "settings.voice"
        static let textSize = "settings.textSize"
    }
}
