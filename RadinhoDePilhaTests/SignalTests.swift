import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Event cues")
struct EventCueTests {
    private let match = SampleMatches.liveComeback

    private func event(_ kind: MatchEventKind, team: Team) -> MatchEvent {
        MatchEvent(
            kind: kind,
            minute: 10,
            stoppageMinute: nil,
            team: team,
            player: "Jogador",
            relatedPlayer: nil,
            detail: nil
        )
    }

    @Test("Everything that changes the score shares the goal cue")
    func scoringEventsShareOneCue() {
        for kind in [MatchEventKind.goal, .ownGoal, .penaltyScored] {
            let cue = EventCue(event: event(kind, team: SampleMatches.nautico), in: match)

            #expect(cue?.kind == .goal)
        }
    }

    @Test("A second yellow card is signalled as a sending off")
    func secondYellowIsASendingOff() {
        let cue = EventCue(event: event(.secondYellowCard, team: SampleMatches.nautico), in: match)

        #expect(cue?.kind == .redCard)
    }

    @Test("The cue carries the side the event belongs to")
    func cueCarriesTheSide() {
        let home = EventCue(event: event(.yellowCard, team: SampleMatches.nautico), in: match)
        let away = EventCue(event: event(.yellowCard, team: SampleMatches.crb), in: match)

        #expect(home?.side == .home)
        #expect(away?.side == .away)
    }

    @Test("A whistle belongs to neither side")
    func whistleHasNoSide() {
        let cue = EventCue(event: event(.periodEnd, team: SampleMatches.crb), in: match)

        #expect(cue == EventCue(kind: .whistle, side: .home))
    }

    @Test("An event the app cannot classify has no cue")
    func unknownEventsAreSilent() {
        #expect(EventCue(event: event(.unknown, team: SampleMatches.nautico), in: match) == nil)
    }

    @Test("Narration produced by the engine carries the cue of its event")
    func narrationCarriesItsCue() throws {
        let goal = try #require(match.events.first { $0.kind == .goal })
        let narration = try #require(TemplateNarrationEngine().narrate(goal, in: match))

        // The first goal of the sample match is CRB's, and CRB is the away side.
        #expect(narration.cue == EventCue(kind: .goal, side: .away))
    }

    @Test("The summary is not a match event, so it has no cue")
    func summaryHasNoCue() {
        #expect(TemplateNarrationEngine().summary(of: match).cue == nil)
    }
}

@Suite("Haptic grammar")
struct HapticGrammarTests {
    @Test("Every kind of event has a pattern", arguments: EventCueKind.allCases)
    func everyKindHasAPattern(kind: EventCueKind) {
        #expect(!HapticGrammar.motif(for: kind).isEmpty)
    }

    @Test("Rhythm tells the kinds of event apart")
    func rhythmIdentifiesTheEvent() {
        #expect(HapticGrammar.motif(for: .goal).count == 1)
        #expect(HapticGrammar.motif(for: .yellowCard).count == 2)
        #expect(HapticGrammar.motif(for: .redCard).count == 3)
        #expect(HapticGrammar.motif(for: .substitution).count == 3)
    }

    @Test("Strength follows how much the event weighs", arguments: EventCueKind.allCases)
    func strengthFollowsSeverity(kind: EventCueKind) {
        let peak = HapticGrammar.motif(for: kind).map(\.intensity).max()

        #expect(peak == HapticGrammar.severity(of: kind).intensity)
    }

    @Test("A goal is felt more strongly than a booking, and a booking more than a substitution")
    func severityIsOrdered() {
        let goal = HapticGrammar.severity(of: .goal).intensity
        let booking = HapticGrammar.severity(of: .yellowCard).intensity
        let substitution = HapticGrammar.severity(of: .substitution).intensity

        #expect(goal > booking)
        #expect(booking > substitution)
    }

    @Test("The pattern plays once for the home side and twice for the away side")
    func repetitionIdentifiesTheSide() {
        let home = HapticGrammar.pulses(for: EventCue(kind: .goal, side: .home))
        let away = HapticGrammar.pulses(for: EventCue(kind: .goal, side: .away))

        #expect(away.count == home.count * 2)
    }

    @Test("The two repetitions are separated by silence")
    func repetitionsDoNotRunTogether() {
        let motif = HapticGrammar.motif(for: .yellowCard)
        let away = HapticGrammar.pulses(for: EventCue(kind: .yellowCard, side: .away))
        let secondStart = away[motif.count].start

        #expect(secondStart >= HapticGrammar.duration(of: motif) + HapticGrammar.repetitionGap)
    }

    @Test("Pulses never overlap", arguments: EventCueKind.allCases)
    func pulsesDoNotOverlap(kind: EventCueKind) {
        let pulses = HapticGrammar.pulses(for: EventCue(kind: kind, side: .away))

        for (current, next) in zip(pulses, pulses.dropFirst()) {
            #expect(next.start >= current.end - 0.0001)
        }
    }

    @Test("Every kind can be explained in words", arguments: EventCueKind.allCases)
    func everyKindHasAnExplanation(kind: EventCueKind) {
        #expect(HapticGrammar.explanation(for: kind).hasPrefix(kind.displayName))
    }
}

@Suite("Earcons")
struct EarconSynthesizerTests {
    @Test("Each earcon is a well-formed WAV file", arguments: EventCueKind.allCases)
    func producesValidWav(kind: EventCueKind) {
        let data = EarconSynthesizer.wavData(for: kind)
        let sampleCount = EarconSynthesizer.samples(for: kind).count

        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data.count == 44 + sampleCount * 2)
    }

    @Test("Each earcon is short enough not to delay the sentence", arguments: EventCueKind.allCases)
    func earconsAreShort(kind: EventCueKind) {
        #expect(EarconSynthesizer.duration(of: kind) <= 1.0)
    }

    @Test("Each earcon is actually audible", arguments: EventCueKind.allCases)
    func earconsAreNotSilent(kind: EventCueKind) {
        let peak = EarconSynthesizer.samples(for: kind).map { abs(Int($0)) }.max() ?? 0

        #expect(peak > 8_000)
    }

    @Test("No two kinds of event share an earcon")
    func earconsAreDistinct() {
        let all = EventCueKind.allCases.map { EarconSynthesizer.wavData(for: $0) }

        #expect(Set(all).count == EventCueKind.allCases.count)
    }

    @Test("The same kind always yields the same sound")
    func synthesisIsDeterministic() {
        #expect(EarconSynthesizer.wavData(for: .goal) == EarconSynthesizer.wavData(for: .goal))
    }

    @Test("A booking has the same rhythm in sound and in vibration")
    func soundAndVibrationShareRhythm() {
        #expect(
            EarconSynthesizer.tones(for: .yellowCard).count
                == HapticGrammar.motif(for: .yellowCard).count
        )
        #expect(
            EarconSynthesizer.tones(for: .substitution).count
                == HapticGrammar.motif(for: .substitution).count
        )
    }
}

@Suite("Pre-match briefing")
struct PreMatchBriefingTests {
    private let briefing = PreMatchBriefing(
        dates: SpokenDate(timeZone: TimeZone(identifier: "America/Recife") ?? .gmt)
    )

    private let match = SampleMatches.scheduled

    @Test("Says who plays whom and who is at home")
    func namesBothSidesAndTheHost() {
        let text = briefing.text(for: match, relativeTo: match.kickoff)

        #expect(text.contains("CRB e Náutico se enfrentam"))
        #expect(text.contains("Mandante: CRB. Visitante: Náutico."))
    }

    @Test("Names the competition")
    func namesTheCompetition() {
        let text = briefing.text(for: match, relativeTo: match.kickoff)

        #expect(text.contains("Campeonato Brasileiro Série B"))
    }

    @Test("Says the match is today when it is")
    func usesRelativeDay() {
        let anHourBefore = match.kickoff.addingTimeInterval(-3_600)

        #expect(briefing.text(for: match, relativeTo: anHourBefore).contains("hoje"))
    }

    @Test("Tells the listener that narration starts with the match")
    func saysWhatHappensNext() {
        let text = briefing.text(for: match, relativeTo: match.kickoff)

        #expect(text.hasSuffix("A narração começa quando a bola rolar."))
    }
}

@Suite("Signal preferences")
@MainActor
struct SignalPreferencesTests {
    /// A store of its own, so the test neither reads nor disturbs the real preferences.
    private func emptyDefaults() throws -> UserDefaults {
        let name = "signal-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        return defaults
    }

    @Test("Sounds and vibrations are on until switched off")
    func signalsDefaultToOn() throws {
        let settings = AppSettings(defaults: try emptyDefaults())

        #expect(settings.earconsEnabled)
        #expect(settings.hapticsEnabled)
    }

    @Test("Switching a signal off survives a relaunch")
    func switchingOffPersists() throws {
        let defaults = try emptyDefaults()

        AppSettings(defaults: defaults).earconsEnabled = false

        let relaunched = AppSettings(defaults: defaults)
        #expect(!relaunched.earconsEnabled)
        #expect(relaunched.hapticsEnabled)
    }
}
