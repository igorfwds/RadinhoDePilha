import Foundation

/// Dates written to be heard, not read.
///
/// Exists because a formatted date and a spoken date are different things. "24/09 20:30" is fine on
/// screen and useless in audio: the synthesiser reads separators literally, so a listener gets
/// "vinte e quatro barra zero nove" instead of a day and a month. Everything here produces words.
///
/// The weekday is included on purpose, and first. Asked when the next match is, people orient
/// themselves by the day of the week before the date, "quinta" places it, "24 de setembro" only
/// confirms it.
nonisolated struct SpokenDate: Sendable {
    private let calendar: Calendar
    private let locale: Locale

    init(locale: Locale = Locale(identifier: "pt_BR"), timeZone: TimeZone = .current) {
        self.locale = locale

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// A date and time as a spoken phrase: "quinta-feira, 24 de setembro, às 20 e 30".
    ///
    /// Relative wording replaces the weekday when it would be clearer: nobody says "na
    /// quinta-feira" about a match starting in two hours.
    func phrase(for date: Date, relativeTo now: Date = Date()) -> String {
        let day = dayPhrase(for: date, relativeTo: now)
        let time = timePhrase(for: date)

        return "\(day), \(time)"
    }

    /// The day part: "hoje", "amanhã", or the weekday with the date.
    func dayPhrase(for date: Date, relativeTo now: Date = Date()) -> String {
        // Compared against `now` rather than against the real today, so the phrasing is testable
        // and so a caller can ask "what would this have read like at kick-off".
        if calendar.isDate(date, inSameDayAs: now) { return "hoje" }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "amanhã"
        }

        let weekday = formatted(date, format: "EEEE")
        let dayAndMonth = formatted(date, format: "d 'de' MMMM")

        // Within the coming week the weekday alone locates the match; beyond that it stops being
        // useful on its own, because "quinta" could be any of several.
        guard let days = calendar.dateComponents([.day], from: now, to: date).day, days < 7 else {
            return "\(weekday), \(dayAndMonth)"
        }

        return "\(weekday), dia \(dayAndMonth)"
    }

    /// The time part: "às 20 e 30", or "às 16 horas" on the hour.
    ///
    /// Avoids "20:30", which the synthesiser reads as a pair of numbers separated by a symbol.
    func timePhrase(for date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        guard minute > 0 else { return "às \(hour) horas" }

        return "às \(hour) e \(minute)"
    }

    /// Short form for the screen, where symbols are read by the eye rather than aloud.
    func compact(for date: Date) -> String {
        formatted(date, format: "EEEE, d 'de' MMMM 'às' HH:mm")
    }

    // MARK: - Time remaining

    /// How long until a moment, as a spoken sentence: "Faltam 2 horas e 14 minutos".
    ///
    /// Approximate on purpose. Seconds tick on screen for whoever is watching, but a listener asking
    /// "quanto falta?" wants an order of magnitude, and "2 horas, 14 minutos e 37 segundos" is stale
    /// before the sentence ends. Two units at most: days and hours far out, hours and minutes
    /// closer, minutes alone in the last hour.
    func remainingSentence(until date: Date, from now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)

        guard seconds > 0 else { return "Está na hora do jogo." }
        guard seconds >= 60 else { return "Falta menos de um minuto." }

        let parts = remainingParts(seconds: seconds)

        // Singular verb only when the whole remainder is a single unit of one: "Falta 1 hora".
        let verb = parts.count == 1 && parts[0].value == 1 ? "Falta" : "Faltam"
        let spoken = parts.map { "\($0.value) \($0.value == 1 ? $0.singular : $0.plural)" }

        return "\(verb) \(spoken.joined(separator: " e "))."
    }

    private struct Part {
        let value: Int
        let singular: String
        let plural: String
    }

    private func remainingParts(seconds: TimeInterval) -> [Part] {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        let day = Part(value: days, singular: "dia", plural: "dias")
        let hour = Part(value: hours, singular: "hora", plural: "horas")
        let minute = Part(value: minutes, singular: "minuto", plural: "minutos")

        let chosen = days > 0 ? [day, hour] : hours > 0 ? [hour, minute] : [minute]

        return chosen.filter { $0.value > 0 }
    }

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format

        return formatter.string(from: date)
    }
}
