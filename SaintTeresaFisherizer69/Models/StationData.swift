import Foundation

// MARK: - Weather Station Configuration

struct WeatherStation: Sendable {
    let name: String
    let county: String
    let handle: String
    let icon: String
    let latitude: Double
    let longitude: Double
    let cameraImageURL: String?

    init(name: String, county: String, handle: String, icon: String,
         latitude: Double, longitude: Double, cameraImageURL: String? = nil) {
        self.name = name
        self.county = county
        self.handle = handle
        self.icon = icon
        self.latitude = latitude
        self.longitude = longitude
        self.cameraImageURL = cameraImageURL
    }

    var sensorDataURL: URL? {
        URL(string: "https://cdn.weatherstem.com/dashboard/data/dynamic/model/\(county)/\(handle)/latest.json")
    }
}

// MARK: - Station Reading (per-station live data)

struct StationReading: Identifiable, Sendable {
    var id: String { station.handle }
    let station: WeatherStation
    let temperatureF: Double?
    let windSpeedMPH: Double?
    let windGustMPH: Double?
    let windDirectionDeg: Double?
    let windChillF: Double?
    let pressureInHg: Double?
    let humidity: Double?
    let conditionsPhrase: String?
    let conditionsIconCode: Int?
    let waterTemperatureF: Double?
    let timestamp: String?
    let error: String?

    var windSpeedKts: Double? { windSpeedMPH.map { $0 * 0.868976 } }
    var windGustKts: Double? { windGustMPH.map { $0 * 0.868976 } }
    var windCardinal: String? { windDirectionDeg.map { WindUtilities.cardinalDirection(from: $0) } }
    var windArrow: String? { windDirectionDeg.map { WindUtilities.arrowCharacter(from: $0) } }

    var isOnline: Bool { error == nil && timestamp != nil }

    static func empty(station: WeatherStation) -> StationReading {
        StationReading(
            station: station,
            temperatureF: nil, windSpeedMPH: nil, windGustMPH: nil,
            windDirectionDeg: nil, windChillF: nil, pressureInHg: nil,
            humidity: nil, conditionsPhrase: nil, conditionsIconCode: nil,
            waterTemperatureF: nil, timestamp: nil, error: nil
        )
    }

    static func failed(station: WeatherStation, error: String) -> StationReading {
        StationReading(
            station: station,
            temperatureF: nil, windSpeedMPH: nil, windGustMPH: nil,
            windDirectionDeg: nil, windChillF: nil, pressureInHg: nil,
            humidity: nil, conditionsPhrase: nil, conditionsIconCode: nil,
            waterTemperatureF: nil, timestamp: nil, error: error
        )
    }
}
