import Foundation

// MARK: - NOAA CO-OPS Tide Service (Configurable per Location)
//
// Supports two modes based on FishingLocation.TideConfig:
//
//   1. Subordinate station — fetches hi/lo extrema from the harmonic
//      reference station, applies NOAA-published time & height offsets,
//      then cosine-interpolates a smooth hourly curve.
//
//   2. Harmonic (direct) station — fetches hourly predictions directly
//      from the NOAA API with interval=h. No offsets or interpolation.

final class TideService: Sendable {

    // MARK: - Configuration

    private let config: FishingLocation.TideConfig

    init(config: FishingLocation.TideConfig) {
        self.config = config
    }

    /// The station ID we are generating predictions for.
    var activeStationID: String {
        config.subordinateStationID ?? config.referenceStationID
    }

    /// The station name we are generating predictions for.
    var activeStationName: String {
        config.subordinateStationName ?? config.referenceStationName
    }

    private let baseURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

    // MARK: - Public API

    /// Fetches tide predictions for the configured station and time window.
    func fetchPredictions(startDate: Date, endDate: Date) async throws -> [NOAATidePrediction] {
        if config.isSubordinate {
            return try await fetchSubordinatePredictions(startDate: startDate, endDate: endDate)
        } else {
            return try await fetchHourlyDirect(startDate: startDate, endDate: endDate)
        }
    }

    // MARK: - Subordinate Station Path (hi/lo + offsets + cosine interpolation)

    /// Fetches hi/lo extrema from the reference station, applies subordinate
    /// offsets, and returns cosine-interpolated hourly predictions.
    private func fetchSubordinatePredictions(startDate: Date, endDate: Date) async throws -> [NOAATidePrediction] {

        // Pad request window by 1 day on each side so the first/last
        // hours have surrounding extrema for clean interpolation.
        let paddedStart = DateUtilities.calendar.date(byAdding: .day, value: -1, to: startDate)!
        let paddedEnd   = DateUtilities.calendar.date(byAdding: .day, value:  1, to: endDate)!

        // 1. Fetch hi/lo from reference station
        let hiloData = try await fetchHiLo(startDate: paddedStart, endDate: paddedEnd)

        // 2. Apply subordinate time & height offsets
        let adjustedExtrema = applyOffsets(to: hiloData)

        guard adjustedExtrema.count >= 2 else {
            throw TideError.noPredictions
        }

        // 3. Cosine-interpolate to hourly predictions
        let hourly = cosineInterpolate(
            extrema: adjustedExtrema,
            from: startDate,
            to: endDate
        )

        return hourly
    }

    // MARK: - Harmonic Direct Path (hourly from NOAA)

    /// Fetches hourly predictions directly from a harmonic station.
    private func fetchHourlyDirect(startDate: Date, endDate: Date) async throws -> [NOAATidePrediction] {
        let beginStr = DateUtilities.noaaDateParam(from: startDate)
        let endStr   = DateUtilities.noaaDateParam(from: endDate)

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "begin_date",  value: beginStr),
            URLQueryItem(name: "end_date",    value: endStr),
            URLQueryItem(name: "station",     value: config.referenceStationID),
            URLQueryItem(name: "product",     value: "predictions"),
            URLQueryItem(name: "datum",       value: "MLLW"),
            URLQueryItem(name: "time_zone",   value: "lst_ldt"),
            URLQueryItem(name: "interval",    value: "h"),
            URLQueryItem(name: "units",       value: "english"),
            URLQueryItem(name: "format",      value: "json")
        ]

        guard let url = components.url else {
            throw TideError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw TideError.invalidResponse(httpResponse.statusCode)
        }

        let decoded: NOAATideResponse
        do {
            decoded = try JSONDecoder().decode(NOAATideResponse.self, from: data)
        } catch {
            throw TideError.decodingError(error)
        }

        if let noaaError = decoded.error {
            throw TideError.noaaError(noaaError.message)
        }

        guard let predictions = decoded.predictions, !predictions.isEmpty else {
            throw TideError.noPredictions
        }

        return predictions
    }

    // MARK: - Fetch Hi/Lo from Reference Station

    private func fetchHiLo(startDate: Date, endDate: Date) async throws -> [NOAATidePrediction] {
        let beginStr = DateUtilities.noaaDateParam(from: startDate)
        let endStr   = DateUtilities.noaaDateParam(from: endDate)

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "begin_date",  value: beginStr),
            URLQueryItem(name: "end_date",    value: endStr),
            URLQueryItem(name: "station",     value: config.referenceStationID),
            URLQueryItem(name: "product",     value: "predictions"),
            URLQueryItem(name: "datum",       value: "MLLW"),
            URLQueryItem(name: "time_zone",   value: "lst_ldt"),
            URLQueryItem(name: "interval",    value: "hilo"),
            URLQueryItem(name: "units",       value: "english"),
            URLQueryItem(name: "format",      value: "json")
        ]

        guard let url = components.url else {
            throw TideError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw TideError.invalidResponse(httpResponse.statusCode)
        }

        let decoded: NOAATideResponse
        do {
            decoded = try JSONDecoder().decode(NOAATideResponse.self, from: data)
        } catch {
            throw TideError.decodingError(error)
        }

        if let noaaError = decoded.error {
            throw TideError.noaaError(noaaError.message)
        }

        guard let predictions = decoded.predictions, !predictions.isEmpty else {
            throw TideError.noPredictions
        }

        return predictions
    }

    // MARK: - Apply Subordinate Offsets

    /// A single tide extremum (high or low) with its adjusted date and height.
    private struct TideExtremum {
        let date: Date
        let height: Double
        let isHigh: Bool
    }

    /// Applies NOAA subordinate station time/height offsets to each extremum.
    private func applyOffsets(to predictions: [NOAATidePrediction]) -> [TideExtremum] {
        var extrema: [TideExtremum] = []

        for pred in predictions {
            guard let date   = DateUtilities.noaaFormatter.date(from: pred.t),
                  let height = Double(pred.v),
                  let type   = pred.type else { continue }

            let isHigh       = type == "H"
            let timeOffset   = isHigh ? config.highTimeOffsetMin : config.lowTimeOffsetMin
            let heightFactor = isHigh ? config.highHeightFactor  : config.lowHeightFactor

            let adjustedDate = DateUtilities.calendar.date(
                byAdding: .minute, value: timeOffset, to: date
            )!
            let adjustedHeight = height * heightFactor

            extrema.append(TideExtremum(
                date: adjustedDate,
                height: adjustedHeight,
                isHigh: isHigh
            ))
        }

        return extrema.sorted { $0.date < $1.date }
    }

    // MARK: - Cosine Interpolation

    /// Generates hourly tide predictions by cosine-interpolating between
    /// successive extrema. This is the standard NOAA method for producing
    /// subordinate station predictions from reference hi/lo data.
    private func cosineInterpolate(
        extrema: [TideExtremum],
        from startDate: Date,
        to endDate: Date
    ) -> [NOAATidePrediction] {

        var predictions: [NOAATidePrediction] = []
        var currentDate = DateUtilities.hourStart(for: startDate)

        while currentDate <= endDate {
            let height  = interpolatedHeight(at: currentDate, extrema: extrema)
            let timeStr = DateUtilities.noaaFormatter.string(from: currentDate)
            let valStr  = String(format: "%.3f", height)

            predictions.append(NOAATidePrediction(t: timeStr, v: valStr, type: nil))

            currentDate = DateUtilities.calendar.date(
                byAdding: .hour, value: 1, to: currentDate
            )!
        }

        return predictions
    }

    /// Cosine interpolation between the two extrema bracketing the given date.
    ///
    ///     h(t) = h_a + (h_b - h_a) × (1 - cos(π · f)) / 2
    ///
    /// where f = (t - t_a) / (t_b - t_a) and a, b are the surrounding extrema.
    /// This produces the smooth sinusoidal curve characteristic of tidal motion.
    private func interpolatedHeight(at date: Date, extrema: [TideExtremum]) -> Double {
        // Find the two extrema that bracket this date
        var before: TideExtremum?
        var after: TideExtremum?

        for ext in extrema {
            if ext.date <= date { before = ext }
            if ext.date >= date && after == nil { after = ext }
        }

        // Edge: clamp to nearest known extremum
        guard let b = before, let a = after else {
            return (before ?? after)?.height ?? 0
        }

        // Exact match on an extremum
        if b.date == a.date { return b.height }

        // Cosine interpolation
        let totalInterval = a.date.timeIntervalSince(b.date)
        let elapsed       = date.timeIntervalSince(b.date)
        let fraction      = elapsed / totalInterval

        return b.height + (a.height - b.height) * (1 - cos(.pi * fraction)) / 2
    }
}

// MARK: - Tide Errors

enum TideError: LocalizedError {
    case invalidURL
    case decodingError(Error)
    case invalidResponse(Int)
    case noaaError(String)
    case noPredictions

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid tide API URL"
        case .decodingError(let error):
            "Tide data error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            "Tide API returned status \(code)"
        case .noaaError(let message):
            "NOAA error: \(message)"
        case .noPredictions:
            "No tide predictions available"
        }
    }
}
