import Foundation

/// One note of an earcon.
nonisolated struct EarconTone: Hashable, Sendable {
    /// Seconds from the start of the earcon.
    let start: TimeInterval

    let duration: TimeInterval

    /// Pitch at the start of the note, in hertz.
    let frequency: Double

    /// Pitch at the end of the note. Equal to ``frequency`` for a steady note.
    let endFrequency: Double

    /// Vibrato rate in hertz, or 0 for none. What makes the whistle sound like a whistle.
    let vibrato: Double

    init(
        start: TimeInterval,
        duration: TimeInterval,
        frequency: Double,
        endFrequency: Double? = nil,
        vibrato: Double = 0
    ) {
        self.start = start
        self.duration = duration
        self.frequency = frequency
        self.endFrequency = endFrequency ?? frequency
        self.vibrato = vibrato
    }

    var end: TimeInterval { start + duration }
}

/// Generates the earcons as audio, instead of shipping them as recordings.
///
/// Earcons are short abstract motifs, one per kind of event, heard just before the sentence that
/// describes it. Synthesising them from a description keeps each motif reviewable as a few
/// numbers, keeps the rhythm identical to the vibration for the same event (two short notes and
/// two short pulses for a booking), and avoids bundling audio of uncertain licence.
///
/// Pure and deterministic: the same kind always yields the same bytes, with no audio hardware
/// involved, so the output can be asserted on in tests.
nonisolated enum EarconSynthesizer {
    static let sampleRate = 22_050.0

    /// Peak level of a single note, well below full scale so it sits under the voice.
    private static let amplitude = 0.45

    /// Fade at each end of a note, which removes the click an abrupt start would produce.
    private static let fade: TimeInterval = 0.008

    /// Depth of the vibrato, in hertz either side of the pitch.
    private static let vibratoDepth = 150.0

    static func tones(for kind: EventCueKind) -> [EarconTone] {
        switch kind {
        case .goal:
            // Rising major arpeggio, ending on a held note.
            [
                EarconTone(start: 0, duration: 0.11, frequency: 523.25),
                EarconTone(start: 0.11, duration: 0.11, frequency: 659.25),
                EarconTone(start: 0.22, duration: 0.11, frequency: 783.99),
                EarconTone(start: 0.33, duration: 0.26, frequency: 1046.5)
            ]
        case .yellowCard:
            [
                EarconTone(start: 0, duration: 0.10, frequency: 880),
                EarconTone(start: 0.20, duration: 0.10, frequency: 880)
            ]
        case .redCard:
            // The booking motif, then a low held note.
            [
                EarconTone(start: 0, duration: 0.10, frequency: 880),
                EarconTone(start: 0.20, duration: 0.10, frequency: 880),
                EarconTone(start: 0.42, duration: 0.40, frequency: 220)
            ]
        case .substitution:
            [
                EarconTone(start: 0, duration: 0.06, frequency: 1174.66),
                EarconTone(start: 0.12, duration: 0.06, frequency: 1174.66),
                EarconTone(start: 0.24, duration: 0.06, frequency: 1174.66)
            ]
        case .penalty:
            [EarconTone(start: 0, duration: 0.5, frequency: 300, endFrequency: 900)]
        case .varReview:
            // Two descending notes, the shape of an attention chime.
            [
                EarconTone(start: 0, duration: 0.18, frequency: 659.25),
                EarconTone(start: 0.20, duration: 0.30, frequency: 523.25)
            ]
        case .whistle:
            [EarconTone(start: 0, duration: 0.4, frequency: 2800, vibrato: 35)]
        }
    }

    /// Length of the earcon for a kind, in seconds.
    static func duration(of kind: EventCueKind) -> TimeInterval {
        tones(for: kind).map(\.end).max() ?? 0
    }

    /// The earcon as 16-bit mono samples.
    static func samples(for kind: EventCueKind) -> [Int16] {
        let notes = tones(for: kind)
        let frameCount = Int((duration(of: kind) * sampleRate).rounded(.up))

        guard frameCount > 0 else { return [] }

        var mix = [Double](repeating: 0, count: frameCount)

        for tone in notes {
            let first = Int(tone.start * sampleRate)
            let length = Int(tone.duration * sampleRate)
            var phase = 0.0

            for offset in 0..<length where first + offset < frameCount {
                let time = Double(offset) / sampleRate
                let progress = tone.duration > 0 ? time / tone.duration : 0

                var frequency = tone.frequency + (tone.endFrequency - tone.frequency) * progress
                if tone.vibrato > 0 {
                    frequency += vibratoDepth * sin(2 * .pi * tone.vibrato * time)
                }

                // Phase is accumulated rather than computed from time, so a gliding or wavering
                // pitch stays continuous instead of crackling.
                phase += 2 * .pi * frequency / sampleRate

                let fadeIn = min(1, time / fade)
                let fadeOut = min(1, (tone.duration - time) / fade)

                mix[first + offset] += sin(phase) * amplitude * min(fadeIn, fadeOut)
            }
        }

        return mix.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
    }

    /// The earcon as a complete WAV file held in memory.
    static func wavData(for kind: EventCueKind) -> Data {
        let samples = samples(for: kind)
        let byteCount = samples.count * MemoryLayout<Int16>.size

        var data = Data()
        data.reserveCapacity(44 + byteCount)

        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))                 // Size of the format chunk.
        data.appendLittleEndian(UInt16(1))                  // Uncompressed PCM.
        data.appendLittleEndian(UInt16(1))                  // Mono.
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate) * 2)     // Bytes per second.
        data.appendLittleEndian(UInt16(2))                  // Bytes per frame.
        data.appendLittleEndian(UInt16(16))                 // Bits per sample.

        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(byteCount))

        for sample in samples {
            data.appendLittleEndian(sample)
        }

        return data
    }
}

nonisolated private extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        let ordered = value.littleEndian
        let bytes = Swift.withUnsafeBytes(of: ordered) { Array($0) }

        append(contentsOf: bytes)
    }
}
