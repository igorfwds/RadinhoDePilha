import Foundation

/// Proper names for Brazilian clubs, looked up by the name the vendor sends.
///
/// Exists because API-Football is inconsistent about diacritics. It sends `Criciuma`, `Gremio`
/// and `Nautico Recife` stripped, yet `Confiança` and `Ferroviária` intact. On screen that is
/// merely untidy; spoken aloud it is a defect, because the synthesiser pronounces "Criciuma" and
/// "Criciúma" differently and this app's only channel is the spoken one.
///
/// Lookup is by **normalised name** rather than by identifier: the vendor's spelling is folded to
/// lowercase without accents, so `Criciuma`, `criciúma` and `CRICIÚMA` all resolve to the same
/// entry. That makes the table tolerant of the vendor fixing its own data, and of the same club
/// appearing under slightly different casing across endpoints.
///
/// The entries were built from the clubs the API actually returns for Série A, B and C, so the
/// keys are known to match rather than guessed.
///
/// Nicknames and epithets are given to Náutico and to its opponents in the 2026 Série B, the
/// matches the case study follows. ``RadioPhrasebook`` alternates between club name and nickname
/// the way radio commentary does, so a wrong nickname would be broadcast as fact: each one here
/// was checked against the nicknames listed for the club on the Portuguese-language Wikipedia in
/// October 2026, and clubs outside that season keep only their name, which is never wrong.
///
/// Every sentence puts the masculine article before the club ("do Náutico", "pelo Tigre"), so
/// only forms that take it are listed. Ponte Preta is left with its name alone for that reason:
/// its nickname, "Macaca", is feminine, and so is the club's own name, which the narration
/// already gets wrong. Fixing that needs grammatical gender in the domain, not an entry here.
nonisolated enum ClubDirectory {
    private struct Entry {
        let name: String
        let shortName: String
        let nickname: String?
        let epithets: [String]

        init(
            _ shortName: String,
            full: String? = nil,
            nickname: String? = nil,
            epithets: [String] = []
        ) {
            self.shortName = shortName
            self.name = full ?? shortName
            self.nickname = nickname
            self.epithets = epithets
        }
    }

    /// Folds a club name to its lookup key: lowercase, no diacritics, trimmed.
    static func normalised(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a domain team, preferring curated naming and falling back to the vendor's.
    ///
    /// The fallback matters: the table covers the national divisions, and a cup opponent from a
    /// state league must still be narrated. A slightly misspelt name beats silence.
    ///
    /// The crest comes from the vendor rather than from this table: it is an image the vendor hosts
    /// and may move, not a fact about the club worth curating here.
    static func team(id: Int, vendorName: String, logo: String? = nil) -> Team {
        let entry = clubs[normalised(vendorName)]

        return Team(
            id: String(id),
            name: entry?.name ?? vendorName,
            shortName: entry?.shortName ?? vendorName,
            nickname: entry?.nickname,
            crestURL: logo.flatMap(URL.init(string:)),
            epithets: entry?.epithets ?? []
        )
    }

    /// Whether a vendor name is covered, for diagnostics and tests.
    static func knows(_ vendorName: String) -> Bool {
        clubs[normalised(vendorName)] != nil
    }

    // Clubs that two vendors spell differently, so the same entry answers to both keys.

    private static let operario = Entry(
        "Operário",
        full: "Operário Ferroviário Esporte Clube",
        nickname: "Fantasma",
        epithets: ["time alvinegro"]
    )

    private static let atleticoGoianiense = Entry(
        "Atlético Goianiense",
        full: "Atlético Clube Goianiense",
        nickname: "Dragão",
        epithets: ["time rubro-negro"]
    )

    private static let fortaleza = Entry(
        "Fortaleza",
        full: "Fortaleza Esporte Clube",
        nickname: "Leão do Pici",
        epithets: ["time tricolor", "Tricolor de Aço"]
    )

    private static let clubs: [String: Entry] = [
        // MARK: The case study
        "nautico recife": Entry(
            "Náutico",
            full: "Clube Náutico Capibaribe",
            nickname: "Timbu",
            epithets: ["time alvirrubro"]
        ),
        // The plain spelling, for vendors that do not append the city.
        "nautico": Entry(
            "Náutico",
            full: "Clube Náutico Capibaribe",
            nickname: "Timbu",
            epithets: ["time alvirrubro"]
        ),

        // MARK: Série A
        "atletico-mg": Entry("Atlético Mineiro", full: "Clube Atlético Mineiro"),
        "atletico goianiense": atleticoGoianiense,
        // Sportmonks abbreviates the state.
        "atletico go": atleticoGoianiense,
        "atletico paranaense": Entry("Athletico Paranaense", full: "Club Athletico Paranaense"),
        "bahia": Entry("Bahia", full: "Esporte Clube Bahia"),
        "botafogo": Entry("Botafogo", full: "Botafogo de Futebol e Regatas"),
        "ceara": Entry(
            "Ceará",
            full: "Ceará Sporting Club",
            nickname: "Vozão",
            epithets: ["time alvinegro", "Vovô"]
        ),
        "corinthians": Entry("Corinthians", full: "Sport Club Corinthians Paulista"),
        "criciuma": Entry(
            "Criciúma",
            full: "Criciúma Esporte Clube",
            nickname: "Tigre",
            epithets: ["time carvoeiro"]
        ),
        "cruzeiro": Entry("Cruzeiro", full: "Cruzeiro Esporte Clube"),
        "cuiaba": Entry(
            "Cuiabá",
            full: "Cuiabá Esporte Clube",
            nickname: "Dourado",
            epithets: ["time auriverde"]
        ),
        "flamengo": Entry("Flamengo", full: "Clube de Regatas do Flamengo"),
        "fluminense": Entry("Fluminense", full: "Fluminense Football Club"),
        "fortaleza ec": fortaleza,
        // The plain spelling, as Sportmonks sends it.
        "fortaleza": fortaleza,
        "gremio": Entry("Grêmio", full: "Grêmio Foot-Ball Porto Alegrense"),
        "internacional": Entry("Internacional", full: "Sport Club Internacional"),
        "juventude": Entry(
            "Juventude",
            full: "Esporte Clube Juventude",
            nickname: "Papo",
            epithets: ["time alviverde"]
        ),
        "palmeiras": Entry("Palmeiras", full: "Sociedade Esportiva Palmeiras"),
        "rb bragantino": Entry("Bragantino", full: "Red Bull Bragantino"),
        "sao paulo": Entry("São Paulo", full: "São Paulo Futebol Clube"),
        "vasco da gama": Entry("Vasco", full: "Club de Regatas Vasco da Gama"),
        "vitoria": Entry("Vitória", full: "Esporte Clube Vitória"),

        // MARK: Série B
        "america mineiro": Entry(
            "América Mineiro",
            full: "América Futebol Clube",
            nickname: "Coelho"
        ),
        "amazonas": Entry("Amazonas", full: "Amazonas Futebol Clube"),
        "avai": Entry("Avaí", full: "Avaí Futebol Clube", nickname: "Leão da Ilha"),
        "botafogo sp": Entry(
            "Botafogo de Ribeirão Preto",
            nickname: "Pantera",
            epithets: ["time tricolor"]
        ),
        "brusque": Entry("Brusque", full: "Brusque Futebol Clube"),
        "chapecoense-sc": Entry("Chapecoense", full: "Associação Chapecoense de Futebol"),
        "coritiba": Entry("Coritiba", full: "Coritiba Foot Ball Club"),
        "crb": Entry(
            "CRB",
            full: "Clube de Regatas Brasil",
            nickname: "Galo",
            epithets: ["time regatiano", "Galo da Praia"]
        ),
        "csa": Entry("CSA", full: "Centro Sportivo Alagoano"),
        "goias": Entry(
            "Goiás",
            full: "Goiás Esporte Clube",
            nickname: "Verdão",
            epithets: ["time esmeraldino"]
        ),
        "guarani campinas": Entry("Guarani", full: "Guarani Futebol Clube"),
        "ituano": Entry("Ituano", full: "Ituano Futebol Clube"),
        "londrina": Entry(
            "Londrina",
            full: "Londrina Esporte Clube",
            nickname: "Tubarão",
            epithets: ["time alviceleste"]
        ),
        "mirassol": Entry("Mirassol", full: "Mirassol Futebol Clube"),
        "novorizontino": Entry(
            "Novorizontino",
            full: "Grêmio Novorizontino",
            nickname: "Tigre do Vale",
            epithets: ["time aurinegro"]
        ),
        "operario-pr": operario,
        // Sportmonks drops the hyphen.
        "operario pr": operario,
        "paysandu": Entry("Paysandu", full: "Paysandu Sport Club"),
        "ponte preta": Entry("Ponte Preta", full: "Associação Atlética Ponte Preta"),
        "sampaio correa": Entry("Sampaio Corrêa", full: "Sampaio Corrêa Futebol Clube"),
        "sport recife": Entry(
            "Sport",
            full: "Sport Club do Recife",
            nickname: "Leão da Ilha",
            epithets: ["time rubro-negro", "Leão do Norte"]
        ),
        "tombense": Entry("Tombense", full: "Tombense Futebol Clube"),
        "vila nova": Entry(
            "Vila Nova",
            full: "Vila Nova Futebol Clube",
            nickname: "Tigrão",
            epithets: ["time colorado"]
        ),

        // MARK: Série C
        "abc": Entry("ABC", full: "ABC Futebol Clube"),
        "aparecidense": Entry("Aparecidense", full: "Associação Atlética Aparecidense"),
        "athletic club": Entry(
            "Athletic Club",
            nickname: "Esquadrão de Aço",
            epithets: ["time alvinegro"]
        ),
        "botafogo pb": Entry("Botafogo da Paraíba"),
        "caxias": Entry("Caxias", full: "Sociedade Esportiva e Recreativa Caxias do Sul"),
        "confianca": Entry("Confiança", full: "Associação Desportiva Confiança"),
        "ferroviaria": Entry("Ferroviária", full: "Associação Ferroviária de Esportes"),
        "ferroviario": Entry("Ferroviário", full: "Ferroviário Atlético Clube"),
        "figueirense": Entry("Figueirense", full: "Figueirense Futebol Clube"),
        "floresta": Entry("Floresta", full: "Floresta Esporte Clube"),
        "remo": Entry("Remo", full: "Clube do Remo"),
        "sao bernardo": Entry(
            "São Bernardo",
            full: "São Bernardo Futebol Clube",
            nickname: "Tigre do ABC",
            epithets: ["time aurinegro"]
        ),
        "sao jose": Entry("São José"),
        "santos": Entry("Santos", full: "Santos Futebol Clube"),
        "volta redonda": Entry("Volta Redonda", full: "Volta Redonda Futebol Clube"),
        "ypiranga-rs": Entry("Ypiranga", full: "Ypiranga Futebol Clube")
    ]
}
