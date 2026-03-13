import Foundation

// MARK: - Open-Meteo API Response Models

struct OpenMeteoResponse: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let hourly: OpenMeteoHourly
    let daily: OpenMeteoDaily

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, hourly, daily
    }
}

struct OpenMeteoHourly: Codable, Sendable {
    let time: [String]
    let temperature2m: [Double?]
    let windSpeed10m: [Double?]
    let windDirection10m: [Double?]
    let windGusts10m: [Double?]
    let weatherCode: [Int?]
    let precipitation: [Double?]
    let cloudCover: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
        case weatherCode = "weather_code"
        case precipitation
        case cloudCover = "cloud_cover"
    }
}

struct OpenMeteoDaily: Codable, Sendable {
    let time: [String]
    let sunrise: [String]
    let sunset: [String]
}

// MARK: - WeatherSTEM API v2 Response Models

struct WeatherSTEMV2Response: Codable, Sendable {
    let time: String?
    let records: [WeatherSTEMV2Record]

    enum CodingKeys: String, CodingKey {
        case time, records
    }
}

struct WeatherSTEMV2Record: Codable, Sendable {
    let sensorName: String
    let property: String?
    let units: String?
    let id: Int?
    let value: WeatherSTEMValue

    enum CodingKeys: String, CodingKey {
        case sensorName = "sensor_name"
        case property, units, id, value
    }
}

/// Handles WeatherSTEM v2 values that can be either a number or a string.
enum WeatherSTEMValue: Codable, Sendable {
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleVal = try? container.decode(Double.self) {
            self = .number(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let val): val
        case .string(let val): Double(val)
        }
    }
}

// MARK: - WeatherSTEM Conditions Response (via data.weatherstem.com)

struct WeatherSTEMConditionsResponse: Codable, Sendable {
    let wxPhraseLong: String?
    let wxPhraseShort: String?
    let cloudCover: Int?
    let cloudCoverPhrase: String?
    let iconCode: Int?
    let dayOrNight: String?
    let visibility: Double?
}

// MARK: - Parsed Current Conditions

struct CurrentConditions: Sendable {
    let temperatureF: Double?
    let windSpeedMPH: Double?
    let windGustMPH: Double?
    let windDirectionDeg: Double?
    let windChillF: Double?
    let humidity: Double?
    let cloudCoverPercent: Double?
    let solarRadiation: Double?
    let timestamp: String?
    let conditionsPhrase: String?
    let conditionsIconCode: Int?
    let waterTemperatureF: Double?

    var windSpeedKts: Double? {
        windSpeedMPH.map { $0 * 0.868976 }
    }

    var windGustKts: Double? {
        windGustMPH.map { $0 * 0.868976 }
    }

    var windCardinal: String? {
        windDirectionDeg.map { WindUtilities.cardinalDirection(from: $0) }
    }

    var windArrow: String? {
        windDirectionDeg.map { WindUtilities.arrowCharacter(from: $0) }
    }

    static let empty = CurrentConditions(
        temperatureF: nil, windSpeedMPH: nil, windGustMPH: nil,
        windDirectionDeg: nil, windChillF: nil, humidity: nil,
        cloudCoverPercent: nil, solarRadiation: nil, timestamp: nil,
        conditionsPhrase: nil, conditionsIconCode: nil,
        waterTemperatureF: nil
    )
}
