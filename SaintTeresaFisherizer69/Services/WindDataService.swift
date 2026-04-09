import Foundation
import UIKit

// MARK: - Wind Data Service

/// Fetches spatial wind field data from Open-Meteo's HRRR-derived endpoint.
/// Builds a grid of points across the Big Bend bbox and returns one
/// `WindFieldSnapshot` per forecast hour.
actor WindDataService {

    // MARK: - Constants

    /// Default bounding box: ~20nm box around Alligator Harbor / St. Teresa
    static let defaultBBox = GeographicBoundingBox(
        minLat: 29.55,
        maxLat: 30.15,
        minLon: -85.05,
        maxLon: -84.05
    )

    /// Grid resolution for Open-Meteo spatial queries
    private static let gridSize = 16

    private static let baseURL = "https://api.open-meteo.com/v1/forecast"
    private static let cacheFileName = "wind_field_cache.json"

    // MARK: - Public API

    /// Fetches wind snapshots for the given bbox and number of forecast hours.
    /// Returns one snapshot per forecast hour.
    func fetchSnapshots(
        for bbox: GeographicBoundingBox = defaultBBox,
        hours: Int = 18
    ) async throws -> [WindFieldSnapshot] {
        let url = try buildURL(for: bbox, hours: hours)

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WindDataError.invalidResponse(http.statusCode)
        }

        let snapshots = try decodeSnapshots(from: data, bbox: bbox, hours: hours)

        // Cache to disk for offline use
        Task.detached(priority: .utility) {
            await self.cacheToFile(data)
        }

        return snapshots
    }

    /// Loads the most recently cached snapshot array for offline use.
    func loadCachedSnapshots(
        for bbox: GeographicBoundingBox = defaultBBox,
        hours: Int = 18
    ) throws -> [WindFieldSnapshot] {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url) else {
            throw WindDataError.noCache
        }
        return try decodeSnapshots(from: data, bbox: bbox, hours: hours)
    }

    // MARK: - URL Construction

    /// Open-Meteo accepts comma-separated latitude/longitude arrays for multi-point
    /// queries. We build a gridSize x gridSize grid across the bbox.
    private func buildURL(for bbox: GeographicBoundingBox, hours: Int) throws -> URL {
        let latStep = (bbox.maxLat - bbox.minLat) / Double(Self.gridSize - 1)
        let lonStep = (bbox.maxLon - bbox.minLon) / Double(Self.gridSize - 1)

        var lats: [String] = []
        var lons: [String] = []

        for row in 0..<Self.gridSize {
            for col in 0..<Self.gridSize {
                let lat = bbox.minLat + Double(row) * latStep
                let lon = bbox.minLon + Double(col) * lonStep
                lats.append(String(format: "%.4f", lat))
                lons.append(String(format: "%.4f", lon))
            }
        }

        var components = URLComponents(string: Self.baseURL)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: lats.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: lons.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "forecast_hours", value: "\(hours)"),
            URLQueryItem(name: "models", value: "best_match"),
        ]

        guard let url = components?.url else {
            throw WindDataError.invalidURL
        }
        return url
    }

    // MARK: - Decoding

    /// Open-Meteo returns an array of forecast objects (one per grid point) when
    /// given multiple lat/lon pairs. Each object has `hourly.time`,
    /// `hourly.wind_speed_10m`, `hourly.wind_direction_10m`, `hourly.wind_gusts_10m`.
    private func decodeSnapshots(
        from data: Data,
        bbox: GeographicBoundingBox,
        hours: Int
    ) throws -> [WindFieldSnapshot] {
        let gridPoints = Self.gridSize * Self.gridSize

        // Open-Meteo returns either a single object (1 point) or an array (multiple points).
        // For multi-point queries, it returns an array of response objects.
        let pointResponses: [OpenMeteoWindResponse]

        do {
            // Try array first (multi-point query)
            pointResponses = try JSONDecoder().decode([OpenMeteoWindResponse].self, from: data)
        } catch {
            // Fallback: try single response and wrap
            do {
                let single = try JSONDecoder().decode(OpenMeteoWindResponse.self, from: data)
                pointResponses = [single]
            } catch {
                throw WindDataError.decodingError(error)
            }
        }

        guard pointResponses.count >= gridPoints else {
            throw WindDataError.insufficientData
        }

        // Parse time strings from the first point (all points share the same times)
        let timeStrings = pointResponses[0].hourly.time
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate, .withTime, .withColonSeparatorInTime]

        // Also try Open-Meteo's format: "2026-04-08T14:00"
        let omFormatter = DateFormatter()
        omFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        omFormatter.timeZone = TimeZone(identifier: "America/New_York")

        let modelRunTime = Date()
        let hourCount = min(hours, timeStrings.count)

        var snapshots: [WindFieldSnapshot] = []
        snapshots.reserveCapacity(hourCount)

        for h in 0..<hourCount {
            let validTime = omFormatter.date(from: timeStrings[h])
                ?? dateFormatter.date(from: timeStrings[h])
                ?? Date()

            var uArr = [Float](repeating: 0, count: gridPoints)
            var vArr = [Float](repeating: 0, count: gridPoints)
            var sustainedArr = [Float](repeating: 0, count: gridPoints)
            var gustArr = [Float](repeating: 0, count: gridPoints)
            var gustFactorArr = [Float](repeating: 0, count: gridPoints)

            for p in 0..<gridPoints {
                let pr = pointResponses[p]
                let speedKts = Float(pr.hourly.windSpeed10m[h] ?? 0)
                let dirDeg = Float(pr.hourly.windDirection10m[h] ?? 0)
                let gustKts = Float(pr.hourly.windGusts10m[h] ?? Double(speedKts))

                // Convert meteorological direction (from) + speed in knots to U/V in m/s
                // Meteorological: 0 = from N, 90 = from E
                let speedMs = speedKts / 1.94384
                let dirRad = dirDeg * .pi / 180.0
                let u = -speedMs * sin(dirRad)  // Eastward component
                let v = -speedMs * cos(dirRad)  // Northward component

                uArr[p] = u
                vArr[p] = v
                sustainedArr[p] = speedKts
                gustArr[p] = gustKts
                gustFactorArr[p] = gustKts / max(speedKts, 1.0)
            }

            snapshots.append(WindFieldSnapshot(
                bbox: bbox,
                gridWidth: Self.gridSize,
                gridHeight: Self.gridSize,
                u: uArr,
                v: vArr,
                sustainedKnots: sustainedArr,
                gustKnots: gustArr,
                gustFactor: gustFactorArr,
                validTime: validTime,
                modelRunTime: modelRunTime,
                source: "open-meteo-hrrr"
            ))
        }

        return snapshots
    }

    // MARK: - Disk Cache

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.cacheFileName)
    }

    private func cacheToFile(_ data: Data) {
        guard let url = cacheFileURL else { return }
        try? data.write(to: url)
    }
}

// MARK: - Open-Meteo Wind Response Models

private nonisolated struct OpenMeteoWindResponse: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let hourly: OpenMeteoWindHourly
}

private nonisolated struct OpenMeteoWindHourly: Codable, Sendable {
    let time: [String]
    let windSpeed10m: [Double?]
    let windDirection10m: [Double?]
    let windGusts10m: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
    }
}
