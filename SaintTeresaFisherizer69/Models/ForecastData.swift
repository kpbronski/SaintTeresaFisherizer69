import Foundation

// MARK: - Unified Forecast Model

struct ForecastHour: Identifiable, Sendable {
    let date: Date
    var id: Date { date }
    let hourOffset: Int
    let timeLabel: String
    let dayLabel: String

    // Tide
    let tideFt: Double

    // Wind
    let windKts: Double?
    let windDeg: Double?
    let windDir: String?
    let windArrow: String?

    // Weather
    let temperatureF: Double?
    let precipitationMm: Double
    let weatherCode: Int
    let hasRain: Bool

    // Celestial
    let isSunrise: Bool
    let isSunset: Bool

    // Computed
    var isPast: Bool { hourOffset < 0 }
    var isMidnight: Bool {
        DateUtilities.calendar.component(.hour, from: date) == 0
    }
}

// MARK: - Dynamic Chart Stats

struct ForecastStats: Sendable {
    let maxTide: Double
    let minTide: Double
    let maxWind: Double

    var tideRange: Double { max(maxTide - minTide, 0.1) }

    static let fallback = ForecastStats(maxTide: 2.2, minTide: -0.6, maxWind: 16.0)
}
