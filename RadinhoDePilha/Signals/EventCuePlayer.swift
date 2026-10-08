import AVFoundation
import CoreHaptics
import Foundation

/// Anything able to signal a match event without words.
///
/// A protocol so the speech service can be handed a recording double in tests: the real one needs
/// a haptic engine and audio hardware, neither of which exists in a test run.
nonisolated protocol EventCuePlayer: Sendable {
    /// Signals the cue and returns once speech may follow.
    ///
    /// Returns when the sound has ended, not when the vibration has: the sound would mask the
    /// first words of the sentence, while a vibration running on under the voice does no harm.
    func play(_ cue: EventCue) async
}

/// Plays earcons and vibration patterns for match events.
///
/// An `actor` for the same reason the speech service is one: it owns mutable state, the haptic
/// engine and the audio players, that is reached from the speech pump and from the settings
/// screen.
///
/// Both channels can be switched off independently. Not everyone wants sounds over a radio
/// broadcast they are also following, and a phone resting on a table makes vibration pointless.
actor EventCueCenter: EventCuePlayer {
    private var earconsEnabled: Bool
    private var hapticsEnabled: Bool

    /// Created on first use, and only on hardware that has a haptic engine at all.
    private var engine: CHHapticEngine?

    /// One player per kind, built on first use and kept: decoding on every goal would add latency
    /// exactly where it is least welcome.
    private var players: [EventCueKind: AVAudioPlayer] = [:]

    init(earconsEnabled: Bool = true, hapticsEnabled: Bool = true) {
        self.earconsEnabled = earconsEnabled
        self.hapticsEnabled = hapticsEnabled
    }

    func setEarconsEnabled(_ enabled: Bool) {
        earconsEnabled = enabled
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
    }

    func play(_ cue: EventCue) async {
        if hapticsEnabled {
            vibrate(cue)
        }

        if earconsEnabled {
            await sound(cue.kind)
        }
    }

    /// Plays both channels regardless of the switches, and waits for the whole pattern.
    ///
    /// For the learning screen, where the point is to feel and hear the signal in full before the
    /// explanation is spoken, including the second repetition that marks the away side.
    func demonstrate(_ cue: EventCue) async {
        let started = ContinuousClock.now

        vibrate(cue)
        await sound(cue.kind)

        let pattern = HapticGrammar.duration(of: HapticGrammar.pulses(for: cue))
        let remaining = Duration.seconds(pattern) - (ContinuousClock.now - started)

        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }

    // MARK: - Vibration

    private func vibrate(_ cue: EventCue) {
        guard let engine = hapticEngine() else { return }

        let events = HapticGrammar.pulses(for: cue).map { pulse in
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness)
                ],
                relativeTime: pulse.start,
                duration: pulse.duration
            )
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)

            // Started before every pattern rather than once. The system stops the engine when the
            // app is interrupted or left idle, and starting one that is already running costs
            // nothing, which is simpler and safer than tracking its state through callbacks.
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A missed vibration is not worth interrupting the narration over: the sentence that
            // follows carries the same information.
        }
    }

    private func hapticEngine() -> CHHapticEngine? {
        if let engine { return engine }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let created = try? CHHapticEngine()
        else { return nil }

        // Haptics only, so the engine does not claim the audio session the voice is using.
        created.playsHapticsOnly = true
        created.isAutoShutdownEnabled = true
        engine = created

        return created
    }

    // MARK: - Sound

    private func sound(_ kind: EventCueKind) async {
        guard let player = audioPlayer(for: kind) else { return }

        player.currentTime = 0
        player.play()

        // Holds the caller until the earcon has ended, so the voice starts after it and not
        // over it.
        try? await Task.sleep(for: .seconds(player.duration))
    }

    private func audioPlayer(for kind: EventCueKind) -> AVAudioPlayer? {
        if let player = players[kind] { return player }

        guard let player = try? AVAudioPlayer(data: EarconSynthesizer.wavData(for: kind)) else {
            return nil
        }

        player.prepareToPlay()
        players[kind] = player

        return player
    }
}
