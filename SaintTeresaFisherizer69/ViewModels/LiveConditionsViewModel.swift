import SwiftUI

// MARK: - Live Conditions ViewModel

@Observable
@MainActor
final class LiveConditionsViewModel {

    // MARK: - State

    var readings: [StationReading] = []
    var ndbcReading: StationReading?
    var isLoading = true
    var lastUpdated: Date?

    var now: Date = Date()

    // MARK: - Services

    private let service = LiveConditionsService()
    private let ndbcService = NDBCService(buoyID: "42027")

    // MARK: - Lifecycle

    /// Initial load on appearance. Users pull-to-refresh for updates.
    func initialLoad() async {
        await loadData()
    }

    func loadData() async {
        if readings.isEmpty { isLoading = true }

        // Run in a detached-like scope so SwiftUI task cancellation
        // doesn't abort in-flight network requests.
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                async let stationResults = service.fetchAllStations()
                async let buoyResult = fetchBuoyReading()

                readings = await stationResults
                ndbcReading = await buoyResult
                lastUpdated = Date()
                now = Date()
                isLoading = false
                continuation.resume()
            }
        }
    }

    private func fetchBuoyReading() async -> StationReading? {
        try? await ndbcService.fetchStationReading()
    }

    // MARK: - Computed

    var lastUpdatedString: String {
        guard let last = lastUpdated else { return "Loading\u{2026}" }
        let seconds = Int(now.timeIntervalSince(last))
        if seconds < 60 { return "Updated just now" }
        let minutes = seconds / 60
        return "Updated \(minutes) min ago"
    }

    var currentTimeString: String {
        DateUtilities.timeDisplay(from: now)
    }

    var onlineCount: Int {
        readings.filter(\.isOnline).count + (ndbcReading?.isOnline == true ? 1 : 0)
    }

    var totalStationCount: Int {
        LiveConditionsService.stations.count + 1 // +1 for NDBC buoy
    }

    // MARK: - Preview

    static func preview() -> LiveConditionsViewModel {
        let vm = LiveConditionsViewModel()
        vm.isLoading = false
        vm.lastUpdated = Date()

        let phrases = ["Partly Cloudy", "Mostly Cloudy", "Fair", "Windy", "Clear", "Overcast"]
        let icons = [30, 28, 34, 24, 32, 26]

        vm.readings = LiveConditionsService.stations.enumerated().map { idx, station in
            StationReading(
                station: station,
                temperatureF: 62.0 + Double(idx) * 3,
                windSpeedMPH: 8.0 + Double(idx) * 2,
                windGustMPH: 14.0 + Double(idx) * 3,
                windDirectionDeg: 180.0 + Double(idx) * 30,
                windChillF: 58.0 + Double(idx) * 2,
                pressureInHg: 30.01 + Double(idx) * 0.02,
                humidity: 75 + Double(idx) * 3,
                conditionsPhrase: phrases[idx],
                conditionsIconCode: icons[idx],
                waterTemperatureF: nil,
                timestamp: "2026-02-25 14:15:00",
                error: nil
            )
        }
        vm.ndbcReading = StationReading(
            station: WeatherStation(
                name: "C23 Buoy", county: "offshore", handle: "ndbc42027",
                icon: "sensor.fill", latitude: 29.045, longitude: -85.305
            ),
            temperatureF: 73.9,
            windSpeedMPH: 15.6,
            windGustMPH: 19.2,
            windDirectionDeg: 220,
            windChillF: 70.1,
            pressureInHg: 29.98,
            humidity: nil,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: 71.8,
            timestamp: "2026-03-12 05:35 UTC",
            error: nil
        )
        return vm
    }
}
