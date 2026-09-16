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

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format

        return formatter.string(from: date)
    }
}
