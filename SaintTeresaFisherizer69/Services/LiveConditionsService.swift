import Foundation

// MARK: - Live Conditions Service (Individual Station Fetcher)

final class LiveConditionsService: Sendable {

    /// The 9 FSWN stations for the Live tab.
    static let stations: [WeatherStation] = [
        WeatherStation(
            name: "Dog Island",
            county: "franklin", handle: "fswndogisland",
            icon: "pawprint.fill",
            latitude: 29.81, longitude: -84.59,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswndogisland/cumulus/snapshot.jpg"
        ),
        WeatherStation(
            name: "Alligator Point",
            county: "franklin", handle: "fswnalligatorpoint",
            icon: "water.waves",
            latitude: 29.90, longitude: -84.38,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnalligatorpoint/alligatorpointnw/snapshot.jpg"
        ),
        WeatherStation(
            name: "Ochlockonee Boat Ramp",
            county: "franklin", handle: "fswnochlockonee",
            icon: "ferry.fill",
            latitude: 29.97, longitude: -84.39,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnochlockonee/fswnochlockoneenorth/snapshot.jpg"
        ),
        WeatherStation(
            name: "FSU Marine Lab",
            county: "franklin", handle: "fsucml",
            icon: "building.columns.fill",
            latitude: 29.92, longitude: -84.51,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/fsucml/neptune/snapshot.jpg"
        ),
        WeatherStation(
            name: "SGI Lighthouse",
            county: "franklin", handle: "fswnsgilighthouse",
            icon: "lighthouse.fill",
            latitude: 29.66, longitude: -84.86,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/sgibridge/sunrise/snapshot.jpg"
        ),
        WeatherStation(
            name: "Island View Park",
            county: "franklin", handle: "fswnislandviewpark",
            icon: "binoculars.fill",
            latitude: 29.87, longitude: -84.53,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnislandviewpark/fswnislandviewparksouth/snapshot.jpg"
        ),
        WeatherStation(
            name: "St. Marks Lighthouse",
            county: "wakulla", handle: "fswnstmarks",
            icon: "lighthouse.fill",
            latitude: 30.074, longitude: -84.180,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/wakulla/fswnstmarks/stmarksrefuge/snapshot.jpg"
        ),
        WeatherStation(
            name: "Shell Point Beach",
            county: "wakulla", handle: "fswnspb",
            icon: "beach.umbrella.fill",
            latitude: 30.058, longitude: -84.290,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/wakulla/fswnspb/fswnspbeast/snapshot.jpg"
        ),
        WeatherStation(
            name: "Salinas Park",
            county: "gulf", handle: "fswnsalinaspark",
            icon: "mappin.and.ellipse",
            latitude: 29.686, longitude: -85.312,
            cameraImageURL: "https://cdn.weatherstem.com/skycamera/gulf/fswnsalinaspark/cumulus/snapshot.jpg"
        ),
    ]

    /// Central geocode for conditions phrase lookup (Franklin County coast).
    private let conditionsLatitude = 29.81
    private let conditionsLongitude = -84.59

    private var conditionsURL: URL {
        URL(string: "https://data.weatherstem.com/v3/wx/observations/current?geocode=\(conditionsLatitude),\(conditionsLongitude)&format=json&language=en-US&units=e&apiKey=\(APIKeys.weatherSTEMKey)")!
    }

    // MARK: - Public

    func fetchAllStations() async -> [StationReading] {
        // Fetch conditions phrase once + all station sensor data in parallel
        async let conditionsResult = fetchConditions()
        async let stationResults = fetchAllSensorData()

        let conditions = try? await conditionsResult
        let readings = await stationResults

        // Merge shared conditions phrase into each reading
        guard let wx = conditions else { return readings }

        return readings.map { reading in
            StationReading(
                station: reading.station,
                temperatureF: reading.temperatureF,
                windSpeedMPH: reading.windSpeedMPH,
                windGustMPH: reading.windGustMPH,
                windDirectionDeg: reading.windDirectionDeg,
                windChillF: reading.windChillF,
                pressureInHg: reading.pressureInHg,
                humidity: reading.humidity,
                conditionsPhrase: wx.wxPhraseLong,
                conditionsIconCode: wx.iconCode,
                waterTemperatureF: nil,
                timestamp: reading.timestamp,
                error: reading.error
            )
        }
    }

    // MARK: - Multi-Station Fetch

    private func fetchAllSensorData() async -> [StationReading] {
        await withTaskGroup(of: StationReading.self) { group in
            for station in Self.stations {
                group.addTask { [self] in
                    await self.fetchSingleStation(station)
                }
            }
            var results: [StationReading] = []
            for await result in group {
                results.append(result)
            }
            // Restore original station order
            let order = Self.stations.map(\.handle)
            return results.sorted { a, b in
                let ai = order.firstIndex(of: a.station.handle) ?? 0
                let bi = order.firstIndex(of: b.station.handle) ?? 0
                return ai < bi
            }
        }
    }

    private func fetchSingleStation(_ station: WeatherStation) async -> StationReading {
        guard let url = station.sensorDataURL else {
            return .failed(station: station, error: "Invalid URL")
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return .failed(station: station, error: "HTTP \(httpResponse.statusCode)")
            }

            let v2Response = try JSONDecoder().decode(WeatherSTEMV2Response.self, from: data)

            guard !v2Response.records.isEmpty else {
                return .failed(station: station, error: "No sensor data")
            }

            return parseSensorData(from: v2Response, station: station)
        } catch is CancellationError {
            return .empty(station: station)
        } catch {
            return .failed(station: station, error: error.localizedDescription)
        }
    }

    // MARK: - Sensor Parsing

    private func parseSensorData(from response: WeatherSTEMV2Response, station: WeatherStation) -> StationReading {
        var temperatureF: Double?
        var windSpeedMPH: Double?
        var windGustMPH: Double?
        var windDirectionDeg: Double?
        var windChillF: Double?
        var pressureInHg: Double?
        var humidity: Double?

        for record in response.records {
            guard let numValue = record.value.doubleValue else { continue }

            switch record.sensorName {
            case "Thermometer":
                temperatureF = numValue
            case "Anemometer":
                windSpeedMPH = numValue
            case "10 Minute Wind Gust":
                windGustMPH = numValue
            case "Wind Vane":
                windDirectionDeg = numValue
            case "Wind Chill":
                windChillF = numValue
            case "Barometer":
                pressureInHg = numValue
            case "Hygrometer":
                humidity = numValue
            default:
                break
            }
        }

        return StationReading(
            station: station,
            temperatureF: temperatureF,
            windSpeedMPH: windSpeedMPH,
            windGustMPH: windGustMPH,
            windDirectionDeg: windDirectionDeg,
            windChillF: windChillF,
            pressureInHg: pressureInHg,
            humidity: humidity,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: nil,
            timestamp: response.time,
            error: nil
        )
    }

    // MARK: - Conditions Phrase

    private func fetchConditions() async throws -> WeatherSTEMConditionsResponse {
        var request = URLRequest(url: conditionsURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw WeatherSTEMError.invalidResponse(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(WeatherSTEMConditionsResponse.self, from: data)
    }
}
