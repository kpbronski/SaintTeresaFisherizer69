import SwiftUI

// MARK: - Live View (Cameras + Conditions)

struct LiveConditionsView: View {
    @State var viewModel = LiveConditionsViewModel()
    @State private var nowPulse: Bool = false
    @State private var refreshToken = 0
    @State private var expandedCameraURL: String?

    var body: some View {
        ZStack {
            backgroundLayer

            if viewModel.isLoading && viewModel.readings.isEmpty {
                loadingView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerSection

                        ForEach(viewModel.readings) { reading in
                            stationCard(reading)
                        }

                        if let buoyReading = viewModel.ndbcReading {
                            buoyCard(buoyReading)
                        }

                        footerSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .refreshable {
                    await viewModel.loadData()
                    refreshToken += 1
                }
            }

            // Fullscreen camera overlay
            if let cameraURL = expandedCameraURL {
                fullscreenOverlay(cameraURL)
                    .transition(.opacity)
            }
        }
        .task {
            await viewModel.initialLoad()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                nowPulse = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Live")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("FSWN Stations & NDBC Buoys")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 6) {
                Text(viewModel.currentTimeString)
                    .foregroundStyle(.white.opacity(0.85))
                Text("·")
                    .foregroundStyle(.white.opacity(0.4))
                Text(viewModel.lastUpdatedString)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 15, weight: .medium))

            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.brightGreen)
                    .frame(width: 6, height: 6)
                    .opacity(nowPulse ? 1.0 : 0.4)
                Text("\(viewModel.onlineCount)/\(viewModel.totalStationCount) stations online")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 12, weight: .medium))

            Text("Pull down to refresh")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    // MARK: - Station Card (with optional camera)

    private func stationCard(_ reading: StationReading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: reading.station.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.teal)
                Text(reading.station.name.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.teal)
                    .tracking(1.5)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(reading.isOnline ? Theme.brightGreen : Theme.windYellow)
                        .frame(width: 6, height: 6)
                        .opacity(nowPulse ? 1.0 : 0.4)
                        .shadow(color: (reading.isOnline ? Theme.brightGreen : Theme.windYellow).opacity(0.8), radius: 4)
                    Text(reading.isOnline ? "LIVE" : "OFFLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle((reading.isOnline ? Theme.brightGreen : Theme.windYellow).opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            Rectangle()
                .fill(Theme.teal.opacity(0.2))
                .frame(height: 0.5)

            // Camera image (if available)
            if let cameraURL = reading.station.cameraImageURL {
                cameraImageView(cameraURL, stationName: reading.station.name)
            }

            // Station handle & timestamp
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.gold.opacity(0.6))
                Text("WeatherSTEM · \(reading.station.handle)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                Spacer()
                if let ts = reading.timestamp {
                    Text(ts)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .padding(.bottom, 4)

            // Metric grid
            if reading.isOnline {
                metricGrid(reading)
            } else {
                offlineMessage(reading)
            }
        }
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.teal.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reading.station.name) station conditions")
    }

    // MARK: - Camera Image

    private func cameraImageView(_ urlString: String, stationName: String) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            case .failure:
                cameraFailurePlaceholder
            case .empty:
                cameraLoadingPlaceholder
            @unknown default:
                cameraLoadingPlaceholder
            }
        }
        .id("\(urlString)-\(refreshToken)")
        .frame(height: 200)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedCameraURL = urlString
            }
        }
        .accessibilityLabel("\(stationName) camera feed. Tap to enlarge.")
    }

    private var cameraLoadingPlaceholder: some View {
        ZStack {
            Theme.deepGulf
            ProgressView()
                .tint(Theme.teal.opacity(0.5))
        }
        .frame(height: 200)
    }

    private var cameraFailurePlaceholder: some View {
        ZStack {
            Theme.deepGulf
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.windYellow.opacity(0.6))
                Text("Feed Unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: 200)
    }

    // MARK: - Fullscreen Camera Overlay

    private func fullscreenOverlay(_ cameraURL: String) -> some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedCameraURL = nil
                    }
                }

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expandedCameraURL = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .accessibilityLabel("Close fullscreen view")
                }
                .padding(.horizontal, 20)

                AsyncImage(url: URL(string: cameraURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.windYellow.opacity(0.6))
                            Text("Feed Unavailable")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .empty:
                        ProgressView()
                            .tint(Theme.teal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
                .id("full-\(cameraURL)-\(refreshToken)")
                .padding(.horizontal, 12)

                Text("Tap anywhere to close")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Metric Grid

    private func metricGrid(_ reading: StationReading) -> some View {
        VStack(spacing: 6) {
            // Row 1: Wind, Gusts, Temp
            HStack(spacing: 0) {
                ConditionMetricView(
                    symbol: "wind",
                    label: "WIND",
                    value: formatWindKts(reading.windSpeedKts),
                    detail: windDetail(reading),
                    accentColor: windColorForOptional(reading.windSpeedKts)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "wind.snow",
                    label: "GUSTS",
                    value: formatWindKts(reading.windGustKts),
                    detail: gustDetail(reading),
                    accentColor: windColorForOptional(reading.windGustKts)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "thermometer.medium",
                    label: "TEMP",
                    value: formatTemp(reading.temperatureF),
                    detail: "Fahrenheit",
                    accentColor: tempColor(reading.temperatureF)
                )
            }

            Rectangle()
                .fill(Theme.teal.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, 8)

            // Row 2: Wind Chill, Conditions, Pressure
            HStack(spacing: 0) {
                ConditionMetricView(
                    symbol: "thermometer.snowflake",
                    label: "WIND CHILL",
                    value: formatTemp(reading.windChillF),
                    detail: "Feels Like",
                    accentColor: chillColor(reading.windChillF)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: conditionsSymbol(reading),
                    label: "CONDITIONS",
                    value: reading.conditionsPhrase ?? "--",
                    detail: conditionsDetail(reading),
                    accentColor: conditionsAccentColor(reading)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "barometer",
                    label: "PRESSURE",
                    value: formatPressure(reading.pressureInHg),
                    detail: "inHg",
                    accentColor: pressureColor(reading.pressureInHg)
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    // MARK: - NDBC Buoy Card

    private func buoyCard(_ reading: StationReading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: reading.station.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.teal)
                Text(reading.station.name.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.teal)
                    .tracking(1.5)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(reading.isOnline ? Theme.brightGreen : Theme.windYellow)
                        .frame(width: 6, height: 6)
                        .opacity(nowPulse ? 1.0 : 0.4)
                        .shadow(color: (reading.isOnline ? Theme.brightGreen : Theme.windYellow).opacity(0.8), radius: 4)
                    Text(reading.isOnline ? "LIVE" : "OFFLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle((reading.isOnline ? Theme.brightGreen : Theme.windYellow).opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            Rectangle()
                .fill(Theme.teal.opacity(0.2))
                .frame(height: 0.5)

            // Attribution
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.gold.opacity(0.6))
                Text("NDBC · 42027 · 45m depth")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                Spacer()
                if let ts = reading.timestamp {
                    Text(ts)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .padding(.bottom, 4)

            if reading.isOnline {
                buoyMetricGrid(reading)
            } else {
                offlineMessage(reading)
            }
        }
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.teal.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("C23 Buoy conditions")
    }

    private func buoyMetricGrid(_ reading: StationReading) -> some View {
        VStack(spacing: 6) {
            // Row 1: Wind, Gusts, Temp
            HStack(spacing: 0) {
                ConditionMetricView(
                    symbol: "wind",
                    label: "WIND",
                    value: formatWindKts(reading.windSpeedKts),
                    detail: windDetail(reading),
                    accentColor: windColorForOptional(reading.windSpeedKts)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "wind.snow",
                    label: "GUSTS",
                    value: formatWindKts(reading.windGustKts),
                    detail: gustDetail(reading),
                    accentColor: windColorForOptional(reading.windGustKts)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "thermometer.medium",
                    label: "TEMP",
                    value: formatTemp(reading.temperatureF),
                    detail: "Fahrenheit",
                    accentColor: tempColor(reading.temperatureF)
                )
            }

            Rectangle()
                .fill(Theme.teal.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, 8)

            // Row 2: Wind Chill, Water Temp, Pressure
            HStack(spacing: 0) {
                ConditionMetricView(
                    symbol: "thermometer.snowflake",
                    label: "WIND CHILL",
                    value: formatTemp(reading.windChillF),
                    detail: "Feels Like",
                    accentColor: chillColor(reading.windChillF)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "water.waves",
                    label: "WATER TEMP",
                    value: formatTemp(reading.waterTemperatureF),
                    detail: "Sea Surface",
                    accentColor: waterTempColor(reading.waterTemperatureF)
                )
                ConditionDividerView()
                ConditionMetricView(
                    symbol: "barometer",
                    label: "PRESSURE",
                    value: formatPressure(reading.pressureInHg),
                    detail: "inHg",
                    accentColor: pressureColor(reading.pressureInHg)
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    private func waterTempColor(_ tempF: Double?) -> Color {
        guard let f = tempF else { return .white.opacity(0.5) }
        if f < 65 { return Color(hex: "64B5F6") }
        if f < 75 { return Theme.brightGreen }
        if f < 82 { return Theme.windYellow }
        return Theme.windRed
    }

    // MARK: - Offline Message

    private func offlineMessage(_ reading: StationReading) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.windYellow.opacity(0.6))
            Text(reading.error ?? "Station offline")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
    }

    // MARK: - Formatting Helpers

    private func formatWindKts(_ kts: Double?) -> String {
        guard let kts else { return "--" }
        return "\(Int(round(kts))) kts"
    }

    private func formatTemp(_ tempF: Double?) -> String {
        guard let tempF else { return "--" }
        return "\(Int(round(tempF)))°F"
    }

    private func formatPressure(_ pressure: Double?) -> String {
        guard let pressure else { return "--" }
        return String(format: "%.2f", pressure)
    }

    private func windDetail(_ reading: StationReading) -> String {
        guard let dir = reading.windCardinal, let arrow = reading.windArrow else { return "Loading…" }
        return "\(dir) \(arrow)"
    }

    private func gustDetail(_ reading: StationReading) -> String {
        guard let gustMPH = reading.windGustMPH else { return "Loading…" }
        return "\(Int(round(gustMPH))) mph"
    }

    // MARK: - Conditions Helpers

    private func conditionsSymbol(_ reading: StationReading) -> String {
        guard let code = reading.conditionsIconCode else { return "cloud.fill" }
        return WindUtilities.conditionSymbol(iconCode: code)
    }

    private func conditionsDetail(_ reading: StationReading) -> String {
        if let h = reading.humidity {
            return "\(Int(h))% humidity"
        }
        return "WeatherSTEM"
    }

    private func conditionsAccentColor(_ reading: StationReading) -> Color {
        guard let code = reading.conditionsIconCode else { return .white.opacity(0.5) }
        let c = WindUtilities.conditionColor(iconCode: code)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    // MARK: - Color Coding

    private func windColorForOptional(_ kts: Double?) -> Color {
        guard let kts else { return Theme.brightGreen }
        return windColor(for: kts)
    }

    private func tempColor(_ tempF: Double?) -> Color {
        guard let f = tempF else { return .white }
        if f < 50 { return Color(hex: "64B5F6") }
        if f < 70 { return Theme.brightGreen }
        if f < 85 { return Theme.windYellow }
        return Theme.windRed
    }

    private func chillColor(_ chillF: Double?) -> Color {
        guard let f = chillF else { return .white }
        if f < 40 { return Color(hex: "42A5F5") }
        if f < 55 { return Color(hex: "64B5F6") }
        if f < 70 { return Theme.brightGreen }
        return Theme.windYellow
    }

    private func pressureColor(_ pressure: Double?) -> Color {
        guard let p = pressure else { return .white.opacity(0.5) }
        if p < 29.50 { return Theme.windRed }
        if p < 29.85 { return Theme.windYellow }
        if p > 30.20 { return Color(hex: "64B5F6") }
        return Theme.brightGreen
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.teal)
            Text("Fetching station data…")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityLabel("Loading station conditions")
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Developed by Bronski Crab Labs")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.35))
            Text("WeatherSTEM FSWN Network · NDBC Buoy Network")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.top, 8)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        OceanBackgroundView()
    }
}

// MARK: - Preview

#Preview {
    LiveConditionsView(viewModel: .preview())
        .preferredColorScheme(.dark)
}
