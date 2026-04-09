import SwiftUI

// MARK: - Wind Overlay Badge

/// Top-corner badge shown when the wind heatmap layer is active.
/// Shows: source, valid time, age, staleness warning, and
/// a one-line plain-language wind summary.
struct WindOverlayBadge: View {

    let snapshot: WindFieldSnapshot?
    let isOffline: Bool

    private var validTime: Date? { snapshot?.validTime }
    private var source: String { snapshot?.source ?? "HRRR" }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(badgeAccentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isStale {
                        Text("STALE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    if isOffline {
                        Text("OFFLINE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.orange)
                    }

                    Text(sourceLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(summaryLine)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Capsule()
                        .fill(Theme.deepGulf.opacity(0.7))
                )
                .overlay(
                    Capsule()
                        .stroke(badgeBorderColor, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Computed Properties

    private var ageHours: Double {
        guard let validTime else { return 0 }
        return Date().timeIntervalSince(validTime) / 3600
    }

    private var isStale: Bool { ageHours > 3 }

    private var badgeAccentColor: Color {
        if isStale || isOffline { return .orange }
        return Theme.teal
    }

    private var badgeBorderColor: Color {
        if isStale || isOffline { return .orange.opacity(0.3) }
        return Theme.teal.opacity(0.2)
    }

    private var sourceLabel: String {
        guard snapshot != nil else { return "HRRR" }

        let timeStr = validTime.map { formatTime($0) } ?? "--:--"
        let ageStr = formatAge(ageHours)

        if isOffline {
            return "last update \(ageStr)"
        }
        return "HRRR \(timeStr) \(ageStr)"
    }

    /// Plain-language wind summary generated from the center of the grid.
    private var summaryLine: String {
        guard let snapshot else { return "Loading wind data..." }

        let centerIdx = (snapshot.gridHeight / 2) * snapshot.gridWidth + (snapshot.gridWidth / 2)
        guard centerIdx < snapshot.sustainedKnots.count,
              centerIdx < snapshot.u.count,
              centerIdx < snapshot.v.count else {
            return "Wind data available"
        }

        let knots = snapshot.sustainedKnots[centerIdx]
        let u = snapshot.u[centerIdx]
        let v = snapshot.v[centerIdx]

        // Direction the wind is coming FROM (meteorological)
        let fromDeg = atan2(-u, -v) * 180 / .pi
        let normalizedDeg = (Double(fromDeg) + 360).truncatingRemainder(dividingBy: 360)
        let compass = WindUtilities.cardinalDirection(from: normalizedDeg)

        let bucket = speedBucket(Float(knots))

        return "\(bucket) \(compass), \(Int(knots)) kts"
    }

    private func speedBucket(_ knots: Float) -> String {
        switch knots {
        case 0..<3:   "Calm"
        case 3..<7:   "Light"
        case 7..<11:  "Gentle"
        case 11..<15: "Moderate"
        case 15..<19: "Fresh"
        case 19..<24: "Strong"
        default:      "Gale"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: date)
    }

    private func formatAge(_ hours: Double) -> String {
        if hours < 0.5 { return "just now" }
        if hours < 1.5 { return "1h ago" }
        return "\(Int(hours))h ago"
    }

    private var accessibilityText: String {
        let status = isOffline ? "Offline. " : (isStale ? "Stale data. " : "")
        return "\(status)Wind overlay: \(summaryLine)"
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.deepGulf.ignoresSafeArea()

        VStack(spacing: 16) {
            WindOverlayBadge(
                snapshot: WindFieldSnapshot(
                    bbox: WindDataService.defaultBBox,
                    gridWidth: 4, gridHeight: 4,
                    u: [Float](repeating: -2.0, count: 16),
                    v: [Float](repeating: -1.0, count: 16),
                    sustainedKnots: [Float](repeating: 8.0, count: 16),
                    gustKnots: [Float](repeating: 10.0, count: 16),
                    gustFactor: [Float](repeating: 1.25, count: 16),
                    validTime: Date().addingTimeInterval(-3600),
                    modelRunTime: Date().addingTimeInterval(-7200),
                    source: "open-meteo-hrrr"
                ),
                isOffline: false
            )

            WindOverlayBadge(snapshot: nil, isOffline: true)
        }
    }
}
