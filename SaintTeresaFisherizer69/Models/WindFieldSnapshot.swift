import Foundation

// MARK: - Wind Field Data Contract

/// The seam between the data layer and the rendering layer. Every phase
/// consumes or produces this struct. Do not modify its shape without
/// updating all phases.
struct WindFieldSnapshot: Sendable {
    /// Geographic bounding box of the data, WGS84.
    let bbox: GeographicBoundingBox

    /// Grid dimensions. For Open-Meteo Phase 1, expect ~16x16.
    let gridWidth: Int
    let gridHeight: Int

    /// U-component (eastward wind, m/s) row-major, gridWidth * gridHeight floats.
    let u: [Float]

    /// V-component (northward wind, m/s) row-major.
    let v: [Float]

    /// Sustained wind speed (knots), row-major. Derived: sqrt(u^2 + v^2) * 1.94384.
    let sustainedKnots: [Float]

    /// Gust speed (knots), row-major. From wind_gusts_10m field.
    let gustKnots: [Float]

    /// Gust factor, row-major. Derived: gustKnots / max(sustainedKnots, 1.0).
    let gustFactor: [Float]

    /// Forecast valid time (the time these conditions are predicted FOR).
    let validTime: Date

    /// Model run time (when the forecast was generated). Used for staleness UI.
    let modelRunTime: Date

    /// Source identifier, e.g. "open-meteo-hrrr" or "nomads-hrrr".
    let source: String
}

// MARK: - Geographic Bounding Box

struct GeographicBoundingBox: Sendable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

// MARK: - Wind Data Errors

enum WindDataError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse(Int)
    case insufficientData
    case noCache

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid wind data URL"
        case .networkError(let error):
            "Wind data network error: \(error.localizedDescription)"
        case .decodingError(let error):
            "Wind data decode error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            "Wind API returned status \(code)"
        case .insufficientData:
            "Not enough data points in wind response"
        case .noCache:
            "No cached wind data available"
        }
    }
}
