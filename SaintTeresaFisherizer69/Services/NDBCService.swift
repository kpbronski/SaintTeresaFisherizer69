import Foundation

// MARK: - NDBC Real-Time Buoy Data Service

/// Fetches current observations from an NDBC buoy via the real-time text data feed.
/// Data format: space-delimited text with 2 header lines, most recent observation first.
/// Columns: YY MM DD hh mm WDIR WSPD GST WVHT DPD APD MWD PRES ATMP WTMP DEWP VIS PTDY TIDE
final class NDBCService: Sendable {

    private let buoyID: String

    init(buoyID: String) {
        self.buoyID = buoyID
    }

    private var dataURL: URL? {
        URL(string: "https://www.ndbc.noaa.gov/data/realtime2/\(buoyID).txt")
    }

    // MARK: - Public

    /// Fetches and parses the latest buoy observation into `CurrentConditions`.
    func fetchCurrentConditions() async throws -> CurrentConditions {
        let obs = try await fetchLatestObservation()

        let tempF = obs.airTempC.map { WindUtilities.celsiusToFahrenheit($0) }
        let waterTempF = obs.waterTempC.map { WindUtilities.celsiusToFahrenheit($0) }
        let windMPH = obs.windSpeedMS.map { $0 * 2.23694 }
        let gustMPH = obs.gustMS.map { $0 * 2.23694 }
        let pressureInHg = obs.pressureHPa.map { $0 * 0.02953 }
        let windChillF = computeWindChill(tempF: tempF, windMPH: windMPH)

        return CurrentConditions(
            temperatureF: tempF,
            windSpeedMPH: windMPH,
            windGustMPH: gustMPH,
            windDirectionDeg: obs.windDirDeg,
            windChillF: windChillF,
            humidity: nil,
            cloudCoverPercent: nil,
            solarRadiation: nil,
            timestamp: obs.timestamp,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: waterTempF,
            pressureInHg: pressureInHg
        )
    }

    /// Fetches and parses the latest buoy observation into a `StationReading`
    /// for the Live Conditions tab.
    func fetchStationReading() async throws -> StationReading {
        let obs = try await fetchLatestObservation()

        let tempF = obs.airTempC.map { WindUtilities.celsiusToFahrenheit($0) }
        let waterTempF = obs.waterTempC.map { WindUtilities.celsiusToFahrenheit($0) }
        let windMPH = obs.windSpeedMS.map { $0 * 2.23694 }
        let gustMPH = obs.gustMS.map { $0 * 2.23694 }
        let pressureInHg = obs.pressureHPa.map { $0 * 0.02953 }
        let windChillF = computeWindChill(tempF: tempF, windMPH: windMPH)

        let station = WeatherStation(
            name: "C23 Buoy",
            county: "offshore", handle: "ndbc42027",
            icon: "sensor.fill",
            latitude: 29.045, longitude: -85.305
        )

        return StationReading(
            station: station,
            temperatureF: tempF,
            windSpeedMPH: windMPH,
            windGustMPH: gustMPH,
            windDirectionDeg: obs.windDirDeg,
            windChillF: windChillF,
            pressureInHg: pressureInHg,
            humidity: nil,
            conditionsPhrase: nil,
            conditionsIconCode: nil,
            waterTemperatureF: waterTempF,
            timestamp: obs.timestamp,
            error: nil
        )
    }

    // MARK: - Internal Observation Model

    private struct BuoyObservation {
        let timestamp: String
        let windDirDeg: Double?
        let windSpeedMS: Double?
        let gustMS: Double?
        let pressureHPa: Double?
        let airTempC: Double?
        let waterTempC: Double?
    }

    // MARK: - Fetch & Parse

    private func fetchLatestObservation() async throws -> BuoyObservation {
        guard let url = dataURL else { throw NDBCError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NDBCError.invalidResponse(httpResponse.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw NDBCError.decodingError
        }

        return try parseLatestObservation(from: text)
    }

    /// Parses the NDBC real-time text format. Skips 2 header lines, reads first data row.
    /// Columns (0-indexed):
    ///   0:YY 1:MM 2:DD 3:hh 4:mm 5:WDIR 6:WSPD 7:GST 8:WVHT 9:DPD
    ///   10:APD 11:MWD 12:PRES 13:ATMP 14:WTMP 15:DEWP 16:VIS 17:PTDY 18:TIDE
    private func parseLatestObservation(from text: String) throws -> BuoyObservation {
        let lines = text.components(separatedBy: .newlines)

        // Find first data line (skip lines starting with #)
        guard let dataLine = lines.first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw NDBCError.noData
        }

        let fields = dataLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard fields.count >= 15 else { throw NDBCError.noData }

        // Build timestamp from YY MM DD hh mm
        let timestamp = "\(fields[0])-\(fields[1])-\(fields[2]) \(fields[3]):\(fields[4]) UTC"

        return BuoyObservation(
            timestamp: timestamp,
            windDirDeg: parseNDBC(fields[5]),
            windSpeedMS: parseNDBC(fields[6]),
            gustMS: parseNDBC(fields[7]),
            pressureHPa: parseNDBC(fields[12]),
            airTempC: parseNDBC(fields[13]),
            waterTempC: parseNDBC(fields[14])
        )
    }

    /// Parses an NDBC field value. Returns nil for "MM" (missing data marker)
    /// and for values of 99.0 or 999.0 which NDBC uses as missing sentinels.
    private func parseNDBC(_ value: String) -> Double? {
        if value == "MM" { return nil }
        guard let d = Double(value) else { return nil }
        if d == 99.0 || d == 999.0 || d == 9999.0 { return nil }
        return d
    }

    // MARK: - Wind Chill (NWS formula)

    private func computeWindChill(tempF: Double?, windMPH: Double?) -> Double? {
        guard let t = tempF, let w = windMPH, t <= 50, w >= 3 else { return tempF }
        let chill = 35.74 + 0.6215 * t - 35.75 * pow(w, 0.16) + 0.4275 * t * pow(w, 0.16)
        return chill
    }
}

// MARK: - NDBC Errors

enum NDBCError: LocalizedError {
    case invalidURL
    case invalidResponse(Int)
    case decodingError
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid NDBC buoy URL"
        case .invalidResponse(let code):
            "NDBC returned status \(code)"
        case .decodingError:
            "Could not parse NDBC buoy data"
        case .noData:
            "No buoy observations available"
        }
    }
}
