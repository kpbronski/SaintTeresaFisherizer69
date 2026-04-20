import Foundation

// MARK: - Open-Meteo Weather Service

final class WeatherService: Sendable {
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    private let latitude: Double
    private let longitude: Double
    private let timezone = "America/New_York"

    init(config: FishingLocation.WeatherConfig) {
        self.latitude = config.latitude
        self.longitude = config.longitude
    }

    func fetchForecast() async throws -> OpenMeteoResponse {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "hourly", value: "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,weather_code,precipitation,cloud_cover"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: timezone)
        ]

        guard let url = components.url else {
            throw WeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw WeatherError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw WeatherError.decodingError(error)
        }
    }
}

// MARK: - Weather Errors

enum WeatherError: LocalizedError {
    case invalidURL
    case decodingError(Error)
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid weather API URL"
        case .decodingError(let error):
            "Weather data error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            "Weather API returned status \(code)"
        }
    }
}

// MARK: - WeatherSTEM v2 Current Conditions Service (Multi-Station Blend)

/// A WeatherSTEM station with its county, handle, and blend weight.
private struct WeatherSTEMStation {
    let county: String
    let handle: String
    let weight: Double

    var sensorDataURL: URL? {
        URL(string: "https://cdn.weatherstem.com/dashboard/data/dynamic/model/\(county)/\(handle)/latest.json")
    }
}

final class WeatherSTEMService: Sendable {

    private let stations: [WeatherSTEMStation]
    private let latitude: Double
    private let longitude: Double

    init(config: FishingLocation.ConditionsConfig) {
        self.stations = config.stations.map { s in
            WeatherSTEMStation(county: s.county, handle: s.handle, weight: s.weight)
        }
        self.latitude = config.conditionsLatitude
        self.longitude = config.conditionsLongitude
    }

    private var conditionsURL: URL {
        URL(string: "https://data.weatherstem.com/v3/wx/observations/current?geocode=\(latitude),\(longitude)&format=json&language=en-US&units=e&apiKey=\(APIKeys.weatherSTEMKey)")!
    }

    func fetchCurrentConditions() async throws -> CurrentConditions {
        // Fetch all station sensor data + conditions phrase in parallel
        async let blendedResult = fetchBlendedSensorData()
        async let conditionsResult = fetchConditions()

        var conditions = try await blendedResult
        let wxConditions = try? await conditionsResult

        // Merge conditions phrase and cloud cover into the result
        if let wx = wxConditions {
            conditions = CurrentConditions(
                temperatureF: conditions.temperatureF,
                windSpeedMPH: conditions.windSpeedMPH,
                windGustMPH: conditions.windGustMPH,
                windDirectionDeg: conditions.windDirectionDeg,
                windChillF: conditions.windChillF,
                humidity: conditions.humidity,
                cloudCoverPercent: wx.cloudCover.map(Double.init),
                solarRadiation: conditions.solarRadiation,
                timestamp: conditions.timestamp,
                conditionsPhrase: wx.wxPhraseLong,
                conditionsIconCode: wx.iconCode,
                waterTemperatureF: nil,
                pressureInHg: conditions.pressureInHg
            )
        }

        return conditions
    }

    // MARK: - Multi-Station Fetch & Blend

    private func fetchBlendedSensorData() async throws -> CurrentConditions {
        // Fetch all stations concurrently
        let results: [(station: WeatherSTEMStation, conditions: CurrentConditions?)] = await withTaskGroup(
            of: (WeatherSTEMStation, CurrentConditions?).self
        ) { group in
            for station in stations {
                group.addTask { [self] in
                    let result = try? await self.fetchSensorData(from: station)
                    return (station, result)
                }
            }
            var collected: [(WeatherSTEMStation, CurrentConditions?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // At least one station must succeed
        let valid = results.filter { $0.conditions != nil }
        guard !valid.isEmpty else {
            throw WeatherSTEMError.noData
        }

        return blendConditions(results)
    }

    private func blendConditions(
        _ results: [(station: WeatherSTEMStation, conditions: CurrentConditions?)]
    ) -> CurrentConditions {
        // Helper: weighted average of an optional Double field
        func weightedAvg(_ keyPath: KeyPath<CurrentConditions, Double?>) -> Double? {
            var totalWeight = 0.0
            var weightedSum = 0.0
            for (station, conditions) in results {
                guard let c = conditions, let val = c[keyPath: keyPath] else { continue }
                weightedSum += val * station.weight
                totalWeight += station.weight
            }
            guard totalWeight > 0 else { return nil }
            return weightedSum / totalWeight
        }

        // Wind direction needs circular (vector) averaging
        func weightedWindDirection() -> Double? {
            var sinSum = 0.0
            var cosSum = 0.0
            var totalWeight = 0.0
            for (station, conditions) in results {
                guard let c = conditions, let deg = c.windDirectionDeg else { continue }
                let rad = deg * .pi / 180.0
                sinSum += sin(rad) * station.weight
                cosSum += cos(rad) * station.weight
                totalWeight += station.weight
            }
            guard totalWeight > 0 else { return nil }
            let avgRad = atan2(sinSum / totalWeight, cosSum / totalWeight)
            var avgDeg = avgRad * 180.0 / .pi
            if avgDeg < 0 { avgDeg += 360.0 }
            return avgDeg
        }

        // Use the most recent timestamp from any station
        let latestTimestamp = results.compactMap { $0.conditions?.timestamp }.max()

        return CurrentConditions(
            temperatureF: weightedAvg(\.temperatureF),
            windSpeedMPH: weightedAvg(\.windSpeedMPH),
            windGustMPH: weightedAvg(\.windGustMPH),
            windDirectionDeg: weightedWindDirection(),
            windChillF: weightedAvg(\.windChillF),
            humidity: weightedAvg(\.humidity),
            cloudCoverPercent: nil,
            solarRadiation: weightedAvg(\.solarRadiation),
            timestamp: latestTimestamp,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: nil,
            pressureInHg: weightedAvg(\.pressureInHg)
        )
    }

    // MARK: - Single Station Fetch

    private func fetchSensorData(from station: WeatherSTEMStation) async throws -> CurrentConditions {
        guard let url = station.sensorDataURL else { throw WeatherSTEMError.noData }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw WeatherSTEMError.invalidResponse(httpResponse.statusCode)
        }

        let v2Response: WeatherSTEMV2Response
        do {
            v2Response = try JSONDecoder().decode(WeatherSTEMV2Response.self, from: data)
        } catch {
            throw WeatherSTEMError.decodingError(error)
        }

        guard !v2Response.records.isEmpty else {
            throw WeatherSTEMError.noData
        }

        return parseSensorData(from: v2Response)
    }

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

    private func parseSensorData(from response: WeatherSTEMV2Response) -> CurrentConditions {
        var temperatureF: Double?
        var windSpeedMPH: Double?
        var windGustMPH: Double?
        var windDirectionDeg: Double?
        var windChillF: Double?
        var humidity: Double?
        var solarRadiation: Double?
        var pressureInHg: Double?

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
            case "Hygrometer":
                humidity = numValue
            case "Solar Radiation Sensor":
                solarRadiation = numValue
            case "Barometer":
                pressureInHg = numValue
            default:
                break
            }
        }

        return CurrentConditions(
            temperatureF: temperatureF,
            windSpeedMPH: windSpeedMPH,
            windGustMPH: windGustMPH,
            windDirectionDeg: windDirectionDeg,
            windChillF: windChillF,
            humidity: humidity,
            cloudCoverPercent: nil,
            solarRadiation: solarRadiation,
            timestamp: response.time,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: nil,
            pressureInHg: pressureInHg
        )
    }
}

enum WeatherSTEMError: LocalizedError {
    case invalidResponse(Int)
    case apiError(String)
    case noData
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code):
            "WeatherSTEM returned status \(code)"
        case .apiError(let msg):
            "WeatherSTEM: \(msg)"
        case .noData:
            "No station data returned"
        case .decodingError(let error):
            "WeatherSTEM decode error: \(error.localizedDescription)"
        }
    }
}
