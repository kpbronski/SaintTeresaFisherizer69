import Foundation

// MARK: - Date Formatting & Comparison Utilities

enum DateUtilities {

    // MARK: - Calendar

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    // MARK: - Formatters

    /// NOAA date strings: "2026-02-24 00:00"
    static let noaaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Open-Meteo hourly: "2026-02-24T00:00"
    static let openMeteoHourlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Open-Meteo daily dates: "2026-02-24"
    static let openMeteoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// NOAA API date parameter: "20260224"
    private static let noaaParamFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Time display: "6:42 AM"
    private static let timeDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    /// Day label: "Mon 24"
    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    // MARK: - Label Generators

    /// "6AM", "12PM", "1AM"
    static func hourLabel(from date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        let ampm = hour >= 12 ? "PM" : "AM"
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(h12)\(ampm)"
    }

    /// "Mon 24", "Tue 25"
    static func dayLabel(from date: Date) -> String {
        dayLabelFormatter.string(from: date)
    }

    /// "6:42 AM"
    static func timeDisplay(from date: Date) -> String {
        timeDisplayFormatter.string(from: date)
    }

    /// NOAA API param: "20260224"
    static func noaaDateParam(from date: Date) -> String {
        noaaParamFormatter.string(from: date)
    }

    // MARK: - Date Math

    /// Returns the start of the hour containing the given date.
    /// Falls back to the date itself if the calendar can't compute the interval (shouldn't happen for Gregorian).
    static func hourStart(for date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// Start of the current hour.
    static func currentHourStart() -> Date {
        hourStart(for: Date())
    }

    /// Hours between two dates (negative = target is in the past).
    static func hourOffset(for date: Date, relativeTo now: Date) -> Int {
        let nowStart = hourStart(for: now)
        let targetStart = hourStart(for: date)
        return calendar.dateComponents([.hour], from: nowStart, to: targetStart).hour ?? 0
    }
}
