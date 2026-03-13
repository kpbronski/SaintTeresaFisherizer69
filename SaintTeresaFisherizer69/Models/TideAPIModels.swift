import Foundation

// MARK: - NOAA CO-OPS Tide Prediction Response Models

struct NOAATideResponse: Codable, Sendable {
    let predictions: [NOAATidePrediction]?
    let error: NOAAError?
}

struct NOAATidePrediction: Codable, Sendable {
    let t: String    // "2026-02-24 00:00"
    let v: String    // "-0.052" (String representation of Double)
    let type: String? // "H" or "L" for hi/lo predictions, nil for hourly
}

struct NOAAError: Codable, Sendable {
    let message: String
}
