import Foundation

/// Stage of the match a moment belongs to, for phrasing time references.
nonisolated enum MatchPeriod: Sendable {
    case firstHalf
    case secondHalf
    case extraTime

    /// Spoken name of the period.
    var spokenName: String {
        switch self {
        case .firstHalf: "primeiro tempo"
        case .secondHalf: "segundo tempo"
        case .extraTime: "prorrogação"
        }
    }

    /// Derived from the minute, rather than from the provider's free-text detail, which differs
    /// between vendors and would leak their vocabulary into the narration.
    static func containing(minute: Int) -> MatchPeriod {
        switch minute {
        case ..<46: .firstHalf
        case ..<91: .secondHalf
        default: .extraTime
        }
    }
}

/// Wording used to narrate each situation, in Brazilian Portuguese.
///
/// Separated from ``TemplateNarrationEngine`` so that *what* to say stays apart from *how* to
/// say it. The engine decides that a goal is an equaliser; this type decides the sentence. The
/// split is what will later allow the narrator personas described in the project's feature notes
/// to be swapped without touching a single line of match logic.
///
/// Every method returns several alternatives. Repetition is a real defect in an audio-only
/// interface: hearing the identical sentence for the fourth goal of a match is grating in a way
/// that reading it is not. The engine picks among the alternatives deterministically, so variety
/// does not cost reproducibility.
///
/// Alternatives may only rephrase what the data states. None of them may add a fact — no "parou
/// no goleiro" for a missed penalty, no "de fora da área" for a goal — because the provider does
/// not report it, and inventing detail would make the app narrate things that did not happen.
///
/// The wording draws on the conventions of Brazilian radio football commentary as generally
/// known. It is **not** derived from a transcribed corpus. Grounding it in a recorded and
/// transcribed broadcast remains open work, and would strengthen the dissertation considerably.
nonisolated struct RadioPhrasebook: Sendable {
    /// Style this phrasebook speaks in.
    ///
    /// Only some passages vary. Goals, sendings-off and time markers carry the emotion of a
    /// broadcast and so differ by persona; the scoreline and a substitution are statements of
    /// fact, and rewriting them per persona would add variance without adding character.
    let persona: NarratorPersona

    init(persona: NarratorPersona = .classic) {
        self.persona = persona
    }

    // MARK: - Time reference

    func timeMarker(minute: Int, stoppage: Int?, period: MatchPeriod) -> [String] {
        if let stoppage, stoppage > 0 {
            return [
                "Aos \(minute) mais \(stoppage), nos acréscimos.",
                "Nos acréscimos do \(period.spokenName), aos \(minute) mais \(stoppage).",
                "Minuto \(minute) mais \(stoppage)."
            ]
        }

        if persona == .passionate {
            // Shorter, because the point is to get to the event.
            return [
                "Aos \(minute)!",
                "Minuto \(minute)!",
                "Aos \(minute) do \(period.spokenName)!"
            ]
        }

        var options = [
            "Aos \(minute) minutos do \(period.spokenName).",
            "Minuto \(minute) do \(period.spokenName).",
            "Aos \(minute) do \(period.spokenName).",
            "Quando eram decorridos \(minute) minutos do \(period.spokenName).",
            "Na marca de \(minute) minutos."
        ]

        if period == .secondHalf {
            options.append("Aos \(minute) da etapa complementar.")
        }

        if minute >= 80 {
            options.append("Na reta final, aos \(minute) minutos.")
        }

        return options
    }

    // MARK: - Goals

    func goalAnnouncement(team: String, isPenalty: Bool) -> [String] {
        switch persona {
        case .classic:
            if isPenalty {
                return [
                    "Gol de pênalti do \(team)!",
                    "Na cobrança de pênalti, gol do \(team)!",
                    "Converteu! Gol do \(team) de pênalti!"
                ]
            }

            return [
                "Gol do \(team)!",
                "É gol do \(team)!",
                "Balançou a rede! Gol do \(team)!",
                "Bola na rede! Gol do \(team)!",
                "Bola no fundo do gol! Gol do \(team)!"
            ]

        case .passionate:
            // The drawn-out "gooool" is the defining sound of Brazilian radio football. Written
            // with repeated vowels on purpose: the synthesiser lengthens the syllable, which is
            // the closest it gets to the real thing.
            if isPenalty {
                return [
                    "Gooool! De pênalti, gol do \(team)!",
                    "Converteu, converteu! Gooool do \(team)!",
                    "Da marca da cal, é gooool do \(team)!"
                ]
            }

            return [
                "Gooool do \(team)!",
                "Gooool! Que gol do \(team)!",
                "Explode a torcida! Gooool do \(team)!",
                "Balançou a rede, senhoras e senhores! Gooool do \(team)!"
            ]

        case .analytical:
            if isPenalty {
                return [
                    "Gol do \(team), em cobrança de pênalti.",
                    "Pênalti convertido pelo \(team)."
                ]
            }

            return [
                "Gol do \(team).",
                "O \(team) marca.",
                "Gol registrado para o \(team)."
            ]
        }
    }

    func meaning(_ context: GoalContext, scorer: String) -> [String] {
        if persona == .passionate {
            return passionateMeaning(context, scorer: scorer)
        }

        if persona == .analytical {
            return analyticalMeaning(context, scorer: scorer)
        }

        switch context {
        case .opensScore:
            return [
                "\(scorer) abre o placar.",
                "\(scorer) inaugura o marcador.",
                "\(scorer) faz o primeiro do jogo."
            ]
        case .equalises:
            return [
                "\(scorer) empata o jogo.",
                "\(scorer) deixa tudo igual.",
                "\(scorer) marca e o jogo está empatado."
            ]
        case .comeback:
            return [
                "\(scorer) marca e é a virada!",
                "\(scorer) vira o jogo!",
                "Estava atrás e agora está na frente: \(scorer) completa a virada!"
            ]
        case .takesLead:
            return [
                "\(scorer) desempata o jogo.",
                "\(scorer) desfaz o empate.",
                "\(scorer) marca e o empate acabou."
            ]
        case .extendsLead:
            return [
                "\(scorer) amplia a vantagem.",
                "\(scorer) aumenta a diferença.",
                "\(scorer) marca mais um e a vantagem cresce."
            ]
        case .reducesDeficit:
            return [
                "\(scorer) diminui a desvantagem.",
                "\(scorer) reduz a diferença.",
                "\(scorer) marca e a desvantagem diminui."
            ]
        }
    }

    private func passionateMeaning(_ context: GoalContext, scorer: String) -> [String] {
        switch context {
        case .opensScore:
            [
                "\(scorer) abre o placar!",
                "\(scorer) faz o primeiro, e que festa!"
            ]
        case .equalises:
            [
                "\(scorer) empata! Está tudo igual!",
                "\(scorer) deixa tudo igual! Jogo novo!"
            ]
        case .comeback:
            [
                "É a virada! \(scorer) vira o jogo!",
                "Virou! \(scorer) completa a virada, e o estádio vem abaixo!"
            ]
        case .takesLead:
            [
                "\(scorer) desempata! Está na frente!",
                "Acabou o empate! \(scorer) põe na frente!"
            ]
        case .extendsLead:
            [
                "\(scorer) amplia! Que vantagem!",
                "Mais um! \(scorer) aumenta a diferença!"
            ]
        case .reducesDeficit:
            [
                "\(scorer) diminui! Ainda dá!",
                "\(scorer) reduz a diferença! Voltou a acreditar!"
            ]
        }
    }

    private func analyticalMeaning(_ context: GoalContext, scorer: String) -> [String] {
        switch context {
        case .opensScore:
            [
                "\(scorer) abriu o placar.",
                "Primeiro gol da partida, de \(scorer)."
            ]
        case .equalises:
            [
                "\(scorer) igualou o placar.",
                "Gol de empate, marcado por \(scorer)."
            ]
        case .comeback:
            [
                "\(scorer) completou a virada.",
                "Com o gol de \(scorer), a equipe que estava atrás passou à frente."
            ]
        case .takesLead:
            [
                "\(scorer) desfez o empate.",
                "Gol que rompe a igualdade, de \(scorer)."
            ]
        case .extendsLead:
            [
                "\(scorer) ampliou a vantagem.",
                "A diferença aumenta com o gol de \(scorer)."
            ]
        case .reducesDeficit:
            [
                "\(scorer) reduziu a desvantagem.",
                "A diferença diminui com o gol de \(scorer)."
            ]
        }
    }

    func assist(player: String) -> [String] {
        [
            "Com assistência de \(player).",
            "Depois do passe de \(player).",
            "A jogada começou com \(player)."
        ]
    }

    func ownGoal(player: String, team: String, beneficiary: String) -> [String] {
        [
            "Gol contra. \(player), do \(team), marca no próprio gol, e o ponto vai para \(beneficiary).",
            "Que infelicidade. \(player), do \(team), desvia para a própria rede, e o gol é de \(beneficiary).",
            "Gol contra de \(player), do \(team). O ponto fica com \(beneficiary)."
        ]
    }

    func penaltyMissed(player: String, team: String) -> [String] {
        [
            "Pênalti perdido! \(player), do \(team), desperdiça a cobrança.",
            "Perdeu! \(player), do \(team), não converte o pênalti.",
            "Pênalti desperdiçado por \(player), do \(team)."
        ]
    }

    // MARK: - Discipline

    func yellowCard(player: String, team: String) -> [String] {
        [
            "Cartão amarelo para \(player), do \(team).",
            "\(player), do \(team), recebe cartão amarelo.",
            "Amarelo para \(player), do \(team). Fica advertido."
        ]
    }

    func sendingOff(
        player: String,
        team: String,
        isSecondYellow: Bool,
        remainingSpelled: String
    ) -> [String] {
        let cause = isSecondYellow
            ? "Segundo cartão amarelo."
            : "Cartão vermelho!"

        return [
            "\(cause) \(player), do \(team), está expulso. O \(team) fica com \(remainingSpelled) jogadores.",
            "\(cause) Expulso \(player), do \(team), que joga agora com \(remainingSpelled) jogadores.",
            "\(cause) \(player) deixa o campo e o \(team) segue com \(remainingSpelled) jogadores."
        ]
    }

    func varReview() -> [String] {
        [
            "O árbitro revisa a jogada no VAR.",
            "Lance em análise no VAR.",
            "O árbitro foi ao monitor conferir a jogada."
        ]
    }

    // MARK: - Substitutions

    func substitution(team: String, incoming: String?, outgoing: String?) -> [String] {
        switch (outgoing, incoming) {
        case let (outgoing?, incoming?):
            return [
                "Substituição no \(team). Sai \(outgoing), entra \(incoming).",
                "Mexe o \(team): \(incoming) entra no lugar de \(outgoing).",
                "Troca no \(team). \(outgoing) sai para a entrada de \(incoming)."
            ]
        case let (nil, incoming?):
            return [
                "Substituição no \(team). Entra \(incoming).",
                "O \(team) coloca \(incoming) em campo."
            ]
        case let (outgoing?, nil):
            return [
                "Substituição no \(team). Sai \(outgoing).",
                "\(outgoing) deixa o campo pelo \(team)."
            ]
        case (nil, nil):
            return ["Substituição no \(team)."]
        }
    }

    // MARK: - Match flow

    func periodStart(_ period: MatchPeriod) -> [String] {
        switch period {
        case .firstHalf:
            [
                "Bola rolando para o primeiro tempo.",
                "Começa o jogo.",
                "Começa o primeiro tempo."
            ]
        case .secondHalf:
            [
                "Bola rolando para o segundo tempo.",
                "Começa o segundo tempo.",
                "Recomeça o jogo."
            ]
        case .extraTime:
            [
                "Começa a prorrogação.",
                "Bola rolando para a prorrogação."
            ]
        }
    }

    func periodEnd(_ period: MatchPeriod) -> [String] {
        switch period {
        case .firstHalf:
            [
                "Fim do primeiro tempo.",
                "Termina a primeira etapa.",
                "O árbitro encerra o primeiro tempo."
            ]
        case .secondHalf:
            [
                "Fim de jogo.",
                "Termina a partida.",
                "O árbitro encerra o jogo."
            ]
        case .extraTime:
            [
                "Fim da prorrogação.",
                "Termina a prorrogação."
            ]
        }
    }

    // MARK: - Scoreline

    /// Scoreline phrased for listening.
    ///
    /// Comma-separated rather than "dois a um" because the synthesiser pauses on the comma, which
    /// keeps the two numbers from being heard as a single figure.
    func scoreline(homeTeam: String, homeGoals: Int, awayTeam: String, awayGoals: Int) -> [String] {
        [
            "Placar: \(homeTeam) \(homeGoals), \(awayTeam) \(awayGoals).",
            "O placar é \(homeTeam) \(homeGoals), \(awayTeam) \(awayGoals).",
            "Como está o jogo: \(homeTeam) \(homeGoals), \(awayTeam) \(awayGoals).",
            "Agora no placar: \(homeTeam) \(homeGoals), \(awayTeam) \(awayGoals).",
            "Está escrito no placar: \(homeTeam) \(homeGoals), \(awayTeam) \(awayGoals)."
        ]
    }

    // MARK: - Catch-up summary

    /// Opening of the on-demand summary.
    ///
    /// Announces itself as a recap rather than sliding straight into the scoreline. A listener who
    /// asked for the summary while live narration is paused needs to know which of the two they
    /// are hearing, and the opening is the only cue available on an audio-only channel.
    func summaryOpening() -> [String] {
        [
            "Situação do jogo.",
            "Resumo da partida.",
            "Para quem está chegando agora."
        ]
    }

    /// Where the match currently stands in time.
    func summaryStage(period: MatchPeriod, minute: Int) -> [String] {
        [
            "\(period.spokenName.capitalizedFirst), \(minute) minutos.",
            "Estamos aos \(minute) minutos do \(period.spokenName).",
            "\(minute) minutos de \(period.spokenName)."
        ]
    }

    func summaryNotStarted() -> [String] {
        [
            "A partida ainda não começou.",
            "Bola ainda não rolou."
        ]
    }

    func summaryHalfTime() -> [String] {
        [
            "As equipes estão no intervalo.",
            "Intervalo de jogo."
        ]
    }

    func summaryFinished() -> [String] {
        [
            "A partida está encerrada.",
            "Jogo terminado."
        ]
    }

    func summaryGoalless() -> [String] {
        [
            "Ninguém marcou até aqui.",
            "O jogo segue sem gols."
        ]
    }

    /// Who scored for one side.
    ///
    /// Takes names already assembled by the engine, because deciding how to list two or more
    /// scorers is grammar rather than vocabulary, and the engine owns the match facts that say
    /// whether a player scored twice.
    func summaryScorers(team: String, scorers: String) -> [String] {
        [
            "Marcou para o \(team): \(scorers).",
            "Gols do \(team) com \(scorers).",
            "Pelo \(team), \(scorers)."
        ]
    }
}

nonisolated private extension String {
    /// Uppercases the first character only, leaving the rest untouched.
    ///
    /// `capitalized` would turn "primeiro tempo" into "Primeiro Tempo", which reads as a title
    /// rather than as the start of a sentence.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
