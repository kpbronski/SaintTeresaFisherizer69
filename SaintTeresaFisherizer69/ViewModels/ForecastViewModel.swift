import SwiftUI

// MARK: - Forecast ViewModel

@Observable
@MainActor
final class ForecastViewModel {

    // MARK: - State

    var forecastHours: [ForecastHour] = []
    var stats: ForecastStats = .fallback
    var isLoading: Bool = true
    var errorMessage: String?
    var lastUpdated: Date?
    var currentConditions: CurrentConditions = .empty
    var currentCloudCover: Double?
    var weatherSTEMError: String?

    var now: Date = Date()

    /// The active station we generate predictions for.
    var activeStationName: String = ""
    var activeStationID: String = ""

    // MARK: - Location Selection

    /// The currently selected fishing location. Persisted via UserDefaults.
    var selectedLocation: FishingLocation {
        didSet {
            guard oldValue != selectedLocation else { return }
            UserDefaults.standard.set(selectedLocation.rawValue, forKey: "selectedFishingLocation")
            rebuildServices()
            // Clear stale data and reload — suppress animations so the view
            // doesn't flash through intermediate states.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                forecastHours = []
                fishingWindows = []
                currentConditions = .empty
                isLoading = true
                errorMessage = nil
                weatherSTEMError = nil
            }
            loadGeneration += 1
            Task { await loadData() }
        }
    }

    // MARK: - Services

    private var weatherService: WeatherService
    private var tideService: TideService
    private var weatherSTEMService: WeatherSTEMService
    private var ndbcService: NDBCService?

    /// Guards against stale data from interleaved fetches during location switches.
    private var loadGeneration: Int = 0

    // MARK: - Init

    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedFishingLocation")
        let location = stored.flatMap(FishingLocation.init(rawValue:)) ?? .dogIslandReef
        self.selectedLocation = location

        self.weatherService = WeatherService(config: location.weatherConfig)
        self.tideService = TideService(config: location.tideConfig)
        self.weatherSTEMService = WeatherSTEMService(config: location.conditionsConfig)
        self.ndbcService = location.ndbcConfig.map { NDBCService(buoyID: $0.buoyID) }
    }

    private func rebuildServices() {
        let loc = selectedLocation
        weatherService = WeatherService(config: loc.weatherConfig)
        tideService = TideService(config: loc.tideConfig)
        weatherSTEMService = WeatherSTEMService(config: loc.conditionsConfig)
        ndbcService = loc.ndbcConfig.map { NDBCService(buoyID: $0.buoyID) }
    }

    // MARK: - Lifecycle

    /// Initial load on appearance. Users pull-to-refresh for updates.
    func initialLoad() async {
        await loadData()
    }

    // MARK: - Data Loading

    func loadData() async {
        if forecastHours.isEmpty { isLoading = true }
        errorMessage = nil
        weatherSTEMError = nil

        let myGeneration = loadGeneration

        let now = Date()
        guard let startDate = DateUtilities.calendar.date(byAdding: .hour, value: -24, to: now),
              let endDate = DateUtilities.calendar.date(byAdding: .day, value: 16, to: now) else {
            errorMessage = "Unable to compute forecast date range"
            isLoading = false
            return
        }

        do {
            async let weatherResponse = weatherService.fetchForecast()
            async let tidePredictions = tideService.fetchPredictions(
                startDate: startDate, endDate: endDate
            )

            let (weather, tides) = try await (weatherResponse, tidePredictions)

            // Discard stale results if the location changed mid-fetch
            guard myGeneration == loadGeneration else { return }

            activeStationName = tideService.activeStationName
            activeStationID = tideService.activeStationID

            let merged = mergeData(weather: weather, tides: tides, now: now)
            let computedStats = computeStats(from: merged)

            // Extract current cloud cover from Open-Meteo
            currentCloudCover = extractCurrentCloudCover(from: weather, now: now)

            forecastHours = merged
            stats = computedStats
            lastUpdated = Date()
            recomputeFishingWindows()
            isLoading = false

        } catch {
            guard myGeneration == loadGeneration else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }

        // Fetch current conditions independently (don't block on it)
        // Use NDBC buoy data for buoy locations, WeatherSTEM for land stations.
        do {
            let conditions: CurrentConditions
            if let ndbcService {
                conditions = try await ndbcService.fetchCurrentConditions()
            } else {
                conditions = try await weatherSTEMService.fetchCurrentConditions()
            }
            guard myGeneration == loadGeneration else { return }
            currentConditions = conditions
        } catch {
            guard myGeneration == loadGeneration else { return }
            weatherSTEMError = error.localizedDescription
            // Keep existing conditions or empty — non-fatal
        }
    }

    private func extractCurrentCloudCover(from weather: OpenMeteoResponse, now: Date) -> Double? {
        let nowHourStart = DateUtilities.hourStart(for: now)
        for (index, timeStr) in weather.hourly.time.enumerated() {
            if let date = DateUtilities.openMeteoHourlyFormatter.date(from: timeStr) {
                let hourStart = DateUtilities.hourStart(for: date)
                if hourStart == nowHourStart {
                    return weather.hourly.cloudCover[index]
                }
            }
        }
        return nil
    }

    // MARK: - Data Merging

    private func mergeData(
        weather: OpenMeteoResponse,
        tides: [NOAATidePrediction],
        now: Date
    ) -> [ForecastHour] {

        // 1. Build weather lookup keyed on hour-start Date
        var weatherByHour: [Date: Int] = [:]
        for (index, timeStr) in weather.hourly.time.enumerated() {
            if let date = DateUtilities.openMeteoHourlyFormatter.date(from: timeStr) {
                let hourStart = DateUtilities.hourStart(for: date)
                weatherByHour[hourStart] = index
            }
        }

        // 2. Build tide lookup keyed on hour-start Date
        var tideByHour: [Date: Double] = [:]
        for prediction in tides {
            if let date = DateUtilities.noaaFormatter.date(from: prediction.t),
               let value = Double(prediction.v) {
                let hourStart = DateUtilities.hourStart(for: date)
                tideByHour[hourStart] = value
            }
        }

        // 3. Build sunrise/sunset maps (hourStart → exact time)
        var sunriseByHour: [Date: Date] = [:]
        var sunsetByHour: [Date: Date] = [:]

        for srStr in weather.daily.sunrise {
            if let date = DateUtilities.openMeteoHourlyFormatter.date(from: srStr) {
                sunriseByHour[DateUtilities.hourStart(for: date)] = date
            }
        }
        for ssStr in weather.daily.sunset {
            if let date = DateUtilities.openMeteoHourlyFormatter.date(from: ssStr) {
                sunsetByHour[DateUtilities.hourStart(for: date)] = date
            }
        }

        // 4. Determine time window: 24 hours back to 360 hours forward
        let nowHourStart = DateUtilities.hourStart(for: now)
        guard let windowStart = DateUtilities.calendar.date(byAdding: .hour, value: -24, to: nowHourStart),
              let windowEnd = DateUtilities.calendar.date(byAdding: .hour, value: 360, to: nowHourStart) else {
            return []
        }

        // 5. Pre-sort tide keys once for interpolation
        let sortedTideKeys = tideByHour.keys.sorted()

        // 6. Iterate each hour in window and build ForecastHour
        var hours: [ForecastHour] = []
        var currentDate = windowStart

        while currentDate <= windowEnd {
            let offset = DateUtilities.hourOffset(for: currentDate, relativeTo: now)
            let wIdx = weatherByHour[currentDate]
            let tideValue = tideByHour[currentDate] ?? interpolateTide(
                for: currentDate, sortedKeys: sortedTideKeys, lookup: tideByHour
            )

            // Weather data (arrays may contain nulls from Open-Meteo)
            let windKts: Double? = wIdx.flatMap { idx in
                guard let sustained = weather.hourly.windSpeed10m[idx] else { return nil }
                if let gust = weather.hourly.windGusts10m[idx] {
                    return sustained * 0.7 + gust * 0.3
                }
                return sustained
            }
            let windDeg: Double? = wIdx.flatMap { weather.hourly.windDirection10m[$0] }
            let tempC: Double? = wIdx.flatMap { weather.hourly.temperature2m[$0] }
            let precip: Double = wIdx.flatMap { weather.hourly.precipitation[$0] } ?? 0
            let wCode: Int = wIdx.flatMap { weather.hourly.weatherCode[$0] } ?? 0
            let cloudPct: Double? = wIdx.flatMap { weather.hourly.cloudCover[$0] }

            let hour = ForecastHour(
                date: currentDate,
                hourOffset: offset,
                timeLabel: DateUtilities.hourLabel(from: currentDate),
                dayLabel: DateUtilities.dayLabel(from: currentDate),
                tideFt: tideValue,
                windKts: windKts,
                windDeg: windDeg,
                windDir: windDeg.map { WindUtilities.cardinalDirection(from: $0) },
                windArrow: windDeg.map { WindUtilities.arrowCharacter(from: $0) },
                temperatureF: tempC.map { WindUtilities.celsiusToFahrenheit($0) },
                precipitationMm: precip,
                weatherCode: wCode,
                hasRain: WindUtilities.isRainy(weatherCode: wCode),
                cloudCoverPercent: cloudPct,
                isSunrise: sunriseByHour[currentDate] != nil,
                isSunset: sunsetByHour[currentDate] != nil,
                sunriseTime: sunriseByHour[currentDate],
                sunsetTime: sunsetByHour[currentDate]
            )

            hours.append(hour)
            guard let nextDate = DateUtilities.calendar.date(byAdding: .hour, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return hours
    }

    /// Linear interpolation for missing tide data points.
    private func interpolateTide(for date: Date, sortedKeys sorted: [Date], lookup: [Date: Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }

        // Find nearest before and after
        var before: Date?
        var after: Date?

        for d in sorted {
            if d <= date { before = d }
            if d >= date && after == nil { after = d }
        }

        if let b = before, let a = after, b != a,
           let bv = lookup[b], let av = lookup[a] {
            let total = a.timeIntervalSince(b)
            let elapsed = date.timeIntervalSince(b)
            let ratio = total > 0 ? elapsed / total : 0
            return bv + (av - bv) * ratio
        }

        // Edge case: use nearest known value
        if let b = before, let bv = lookup[b] { return bv }
        if let a = after, let av = lookup[a] { return av }
        return 0
    }

    private func computeStats(from hours: [ForecastHour]) -> ForecastStats {
        guard !hours.isEmpty else { return .fallback }

        let tides = hours.map(\.tideFt)
        let winds = hours.compactMap(\.windKts)

        let rawMax = (tides.max() ?? 2.0) + 0.3
        let rawMin = (tides.min() ?? -0.5) - 0.3

        return ForecastStats(
            maxTide: rawMax,
            minTide: rawMin < rawMax ? rawMin : rawMax - 0.1,
            maxWind: max((winds.max() ?? 15.0) + 2.0, 10.0)
        )
    }

    // MARK: - Current Conditions (Computed)

    private var currentHour: ForecastHour? {
        forecastHours.first { $0.hourOffset == 0 }
    }

    private var nextHour: ForecastHour? {
        forecastHours.first { $0.hourOffset == 1 }
    }

    var currentTideString: String {
        guard let hour = currentHour else { return "--" }
        let sign = hour.tideFt >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", hour.tideFt)) ft"
    }

    var currentTideSubtitle: String {
        guard let curr = currentHour, let next = nextHour else { return "Loading\u{2026}" }
        let rate = next.tideFt - curr.tideFt
        let direction = rate >= 0 ? "Rising" : "Falling"
        return "\(direction) \(String(format: "%.1f", abs(rate))) ft/hr"
    }

    /// Current tide rate in ft/hr; positive = rising, negative = falling, nil if no data.
    var currentTideRate: Double? {
        guard let curr = currentHour, let next = nextHour else { return nil }
        return next.tideFt - curr.tideFt
    }

    /// Current tide height in ft, signed; nil if no data.
    var currentTideFt: Double? {
        currentHour?.tideFt
    }

    /// Current wind speed in knots; nil if no data.
    var currentWindKts: Double? {
        currentHour?.windKts
    }

    var currentWindString: String {
        guard let kts = currentHour?.windKts else { return "--" }
        return "\(Int(kts)) kts"
    }

    var currentWindSubtitle: String {
        guard let dir = currentHour?.windDir, let arrow = currentHour?.windArrow else { return "Loading\u{2026}" }
        return "\(dir) \(arrow)"
    }

    var currentWindColor: Color {
        guard let kts = currentHour?.windKts else { return Theme.brightGreen }
        return windColor(for: kts)
    }

    var currentTimeString: String {
        DateUtilities.timeDisplay(from: now)
    }

    var lastUpdatedString: String {
        guard let last = lastUpdated else { return "Loading\u{2026}" }
        let seconds = Int(now.timeIntervalSince(last))
        if seconds < 60 { return "Updated just now" }
        let minutes = seconds / 60
        return "Updated \(minutes) min ago"
    }

    var stationLabel: String {
        selectedLocation.stationLabel
    }

    // MARK: - Fishing Window Filters

    /// User-configurable max wind speed (knots). Default 8.
    var windThresholdKts: Double = 8 {
        didSet { recomputeFishingWindows() }
    }

    /// When true, only show windows during incoming (rising) tide.
    var requireIncomingTide: Bool = false {
        didSet { recomputeFishingWindows() }
    }

    /// Minimum consecutive qualifying hours to form a fishing window. Default 4.
    var minimumWindowHours: Int = 4 {
        didSet { recomputeFishingWindows() }
    }

    // MARK: - Fishing Windows (cached — recomputed on data load or filter change)

    var fishingWindows: [FishingWindow] = []

    private func recomputeFishingWindows() {
        let data = forecastHours
        guard data.count > 1 else { fishingWindows = []; return }
        let daylight = Self.daylightIndexSet(data: data)
        let threshold = windThresholdKts

        var qualifying: [Int] = []
        for i in 1..<data.count {
            let hour = data[i]
            guard hour.hourOffset > 0,
                  daylight.contains(i),
                  let windKts = hour.windKts, windKts < threshold
            else { continue }

            if requireIncomingTide {
                guard data[i].tideFt > data[i - 1].tideFt else { continue }
            }

            qualifying.append(i)
        }
        fishingWindows = groupIntoWindows(indices: qualifying, data: data)
    }

    static func daylightIndexSet(data: [ForecastHour]) -> Set<Int> {
        let ranges = computeDaylightRanges(data: data)
        var indices = Set<Int>()
        for range in ranges {
            for i in range.start...range.end {
                indices.insert(i)
            }
        }
        return indices
    }

    private func groupIntoWindows(indices: [Int], data: [ForecastHour]) -> [FishingWindow] {
        guard !indices.isEmpty else { return [] }
        let minHours = minimumWindowHours
        var windows: [FishingWindow] = []
        var current = [indices[0]]

        for i in 1..<indices.count {
            if indices[i] == indices[i - 1] + 1 {
                current.append(indices[i])
            } else {
                if current.count >= minHours {
                    windows.append(FishingWindow(hours: current.map { data[$0] }))
                }
                current = [indices[i]]
            }
        }
        if current.count >= minHours {
            windows.append(FishingWindow(hours: current.map { data[$0] }))
        }
        return windows
    }

    /// Shared daylight range computation used by both the chart and the fisherizer.
    static func computeDaylightRanges(data: [ForecastHour]) -> [(start: Int, end: Int)] {
        var ranges: [(start: Int, end: Int)] = []
        var daylightStart: Int?

        let firstSunrise = data.firstIndex(where: { $0.isSunrise })
        let firstSunset = data.firstIndex(where: { $0.isSunset })

        if let sunset = firstSunset {
            if let sunrise = firstSunrise {
                if sunset < sunrise { daylightStart = 0 }
            } else {
                daylightStart = 0
            }
        }

        for (idx, hour) in data.enumerated() {
            if hour.isSunrise { daylightStart = idx }
            if hour.isSunset, let start = daylightStart {
                ranges.append((start: start, end: idx))
                daylightStart = nil
            }
        }

        if let start = daylightStart {
            ranges.append((start: start, end: data.count - 1))
        }

        return ranges
    }

    // MARK: - Preview Support

    static func preview(location: FishingLocation = .dogIslandReef) -> ForecastViewModel {
        let vm = ForecastViewModel()
        vm.selectedLocation = location
        vm.forecastHours = generatePreviewHours()
        vm.stats = ForecastStats(maxTide: 2.2, minTide: -0.6, maxWind: 16.0)
        vm.isLoading = false
        vm.lastUpdated = Date()
        vm.recomputeFishingWindows()
        vm.currentCloudCover = 35
        vm.currentConditions = CurrentConditions(
            temperatureF: 68.2,
            windSpeedMPH: 14.0,
            windGustMPH: 22.0,
            windDirectionDeg: 206,
            windChillF: 62.5,
            humidity: 78,
            cloudCoverPercent: 35,
            solarRadiation: 455,
            timestamp: "2026-02-25 14:15:00",
            conditionsPhrase: "Partly Cloudy",
            conditionsIconCode: 30,
            waterTemperatureF: nil,
            pressureInHg: 30.12
        )
        return vm
    }

    private static func generatePreviewHours() -> [ForecastHour] {
        let now = DateUtilities.currentHourStart()
        var hours: [ForecastHour] = []

        for i in -24...360 {
            let date = DateUtilities.calendar.date(byAdding: .hour, value: i, to: now)!
            let hourOfDay = DateUtilities.calendar.component(.hour, from: date)

            // Simple sinusoidal tide
            let tidePhase = Double(i) / 12.4 * .pi * 2
            let tide = 0.8 + 1.0 * sin(tidePhase)

            // Simple wind pattern
            let windBase = 6.0 + 5.0 * sin(Double(i) / 8.0)
            let windDeg = (180.0 + Double(i) * 3).truncatingRemainder(dividingBy: 360)

            hours.append(ForecastHour(
                date: date,
                hourOffset: i,
                timeLabel: DateUtilities.hourLabel(from: date),
                dayLabel: DateUtilities.dayLabel(from: date),
                tideFt: tide,
                windKts: i >= 0 ? windBase : nil,
                windDeg: i >= 0 ? windDeg : nil,
                windDir: i >= 0 ? WindUtilities.cardinalDirection(from: windDeg) : nil,
                windArrow: i >= 0 ? WindUtilities.arrowCharacter(from: windDeg) : nil,
                temperatureF: 68 + 8 * sin(Double(hourOfDay - 14) / 24.0 * .pi * 2),
                precipitationMm: 0,
                weatherCode: 0,
                hasRain: false,
                cloudCoverPercent: nil,
                isSunrise: hourOfDay == 7 && i >= 0,
                isSunset: hourOfDay == 18 && i >= 0,
                sunriseTime: (hourOfDay == 7 && i >= 0) ? date : nil,
                sunsetTime: (hourOfDay == 18 && i >= 0) ? date : nil
            ))
        }
        return hours
    }
}
