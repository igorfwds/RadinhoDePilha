import Foundation

/// A narrated excerpt used to preview a persona before choosing it.
///
/// Exists because a persona cannot be judged from its name. "Torcedor" and "Analítico" mean
/// nothing until heard, and for an audience that will listen to this voice for ninety minutes,
/// choosing blind is the wrong way round.
///
/// The excerpt is **narrated by the real engine**, not stored as fixed text. That matters twice
/// over: the preview is exactly what the listener will get, and it cannot drift out of date when
/// the phrasebook changes.
///
/// The moment is spoken with its context first, which match, which competition, which year 
/// because a goal announcement with no setting is disorienting when you cannot see a screen
/// explaining that this is a sample.
nonisolated struct PersonaShowcase: Sendable {
    /// Match the excerpt is drawn from.
    let match: Match

    /// Spoken introduction, stating what is about to be heard.
    let context: String

    /// Builds a showcase from a recorded match.
    ///
    /// - Parameters:
    ///   - match: the match to draw from, ideally one whose events include a comeback.
    ///   - context: sentence spoken before the excerpt.
    init(match: Match, context: String) {
        self.match = match
        self.context = context
    }

    /// The excerpt as this persona would say it.
    ///
    /// Returns `nil` only when the match carries no goal at all, which no real fixture used here
    /// would.
    func narration(persona: NarratorPersona) -> String? {
        guard let event = showcaseEvent else { return nil }

        let engine = TemplateNarrationEngine(persona: persona)
        guard let narration = engine.narrate(event, in: match) else { return nil }

        return "\(context) \(narration.text)"
    }

    /// The most telling goal in the match.
    ///
    /// Prefers a goal that completed a comeback, because that is where the personas diverge most:
    /// the classic register reports it, the supporter shouts it, the analytical one describes it.
    /// Falls back to the last goal, then to any goal, so the showcase never comes up empty.
    private var showcaseEvent: MatchEvent? {
        let engine = TemplateNarrationEngine()
        let goals = match.events.filter {
            [.goal, .penaltyScored].contains($0.kind)
        }

        let comeback = goals.first { engine.goalContext(for: $0, in: match) == .comeback }

        return comeback ?? goals.last ?? goals.first
    }
}

nonisolated extension PersonaShowcase {
    /// The showcase shipped with the app.
    ///
    /// The derby: Náutico 1×0 Sport in the 2024 Pernambucano, decided by Patrick Allan at 58
    /// minutes. Chosen over a cup final because a Clássico dos Clássicos won at home is the moment
    /// a Náutico supporter recognises fastest, and recognising the moment is what lets someone
    /// judge a persona by how it *sounds* rather than by what it says.
    ///
    /// It is also the only Náutico win over Sport in the seasons the free plan reaches.
    ///
    /// Not the 2019 promotion decider, which would carry more meaning still: the free plan reaches
    /// only 2022 to 2024, so that match cannot be requested, and inventing a scorer and a minute
    /// for it would put fabricated facts into the artefact. Swap the recording and the context
    /// sentence once a paid plan makes it available.
    static func bundled() -> PersonaShowcase? {
        guard let match = try? RecordedMatches.match(named: RecordedMatches.nauticoSport) else {
            return nil
        }

        return PersonaShowcase(
            match: match,
            context: "Clássico dos Clássicos, Náutico e Sport, pelo Pernambucano de 2024:"
        )
    }

    /// Fallback drawn from hand-built data, for previews and for when no recording is present.
    static func sample() -> PersonaShowcase {
        PersonaShowcase(
            match: SampleMatches.liveComeback,
            context: "Exemplo de narração:"
        )
    }
}
