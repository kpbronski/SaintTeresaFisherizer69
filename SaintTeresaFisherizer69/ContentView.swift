import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @State var viewModel = ForecastViewModel()
    @State private var nowPulse: Bool = false
    @State private var showAbout = false

    var body: some View {
        TabView {
            windTideTab
                .tabItem {
                    Label("Wind & Tide", systemImage: "wind")
                }

            FisherizerView(viewModel: viewModel)
                .tabItem {
                    Label {
                        Text("Dispatcher")
                    } icon: {
                        FisherizerTabIcon()
                    }
                }

            LiveConditionsView()
                .tabItem {
                    Label("Live", systemImage: "video.fill")
                }

            RadarView()
                .tabItem {
                    Label("Crab Command", systemImage: "dot.radiowaves.left.and.right")
                }
        }
        .tint(Theme.teal)
        .transaction { $0.animation = nil }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    // MARK: - Wind & Tide Tab

    private var windTideTab: some View {
        ZStack {
            backgroundLayer

            if viewModel.isLoading && viewModel.forecastHours.isEmpty {
                loadingView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerSection

                        if let error = viewModel.errorMessage {
                            errorBanner(message: error)
                        }

                        conditionCards
                        windTideHorizonCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .refreshable {
                    await viewModel.loadData()
                }
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

    // MARK: - Loading View

    @State private var crabSpin: Double = 0

    private var loadingView: some View {
        VStack(spacing: 16) {
            Text("\u{1F980}")
                .font(.system(size: 48))
                .rotationEffect(.degrees(crabSpin))
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                        crabSpin = 360
                    }
                }
            Text("Hold onto your butts.")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityLabel("Loading forecast data")
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            Spacer()
            Button {
                Task { await viewModel.loadData() }
            } label: {
                Text("Retry")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.teal)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
        .accessibilityLabel("Error: \(message). Tap retry to reload.")
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        OceanBackgroundView()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Text("STB FISHERIZER 69")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .accessibilityLabel("About this app")
            }

            Text("Developed in Bronski Crab Labs")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))

            LocationPickerView(viewModel: viewModel)
        }
        .padding(.top, 4)
    }

    // MARK: - Current Conditions Panel

    private var conditionCards: some View {
        currentConditionsPanel
    }

    private var currentConditionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.teal)
                Text("CURRENT CONDITIONS \(viewModel.selectedLocation.shortName)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.teal)
                    .tracking(1.5)
                Spacer()
                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(conditionsStatusColor)
                        .frame(width: 6, height: 6)
                        .opacity(nowPulse ? 1.0 : 0.4)
                        .shadow(color: conditionsStatusColor.opacity(0.8), radius: 4)
                    Text(conditionsStatusLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(conditionsStatusColor.opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            // Thin separator
            Rectangle()
                .fill(Theme.teal.opacity(0.2))
                .frame(height: 0.5)

            // Station label
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.gold.opacity(0.6))
                Text(viewModel.selectedLocation.conditionsBlendLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                Spacer()
                if let ts = viewModel.currentConditions.timestamp {
                    Text(ts)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .padding(.bottom, 4)

            // Main data grid — 2 rows x 3 columns
            VStack(spacing: 6) {
                // Row 1: Tide, Wind, Gusts
                HStack(spacing: 0) {
                    ConditionMetricView(
                        symbol: "water.waves",
                        label: "TIDE",
                        value: viewModel.currentTideString,
                        detail: viewModel.currentTideSubtitle,
                        accentColor: Theme.teal
                    )
                    ConditionDividerView()
                    ConditionMetricView(
                        symbol: "wind",
                        label: "WIND",
                        value: formatWindKts(viewModel.currentConditions.windSpeedKts),
                        detail: windDetail,
                        accentColor: windMetricColor
                    )
                    ConditionDividerView()
                    ConditionMetricView(
                        symbol: "wind.snow",
                        label: "GUSTS",
                        value: formatWindKts(viewModel.currentConditions.windGustKts),
                        detail: gustDetail,
                        accentColor: gustMetricColor
                    )
                }

                // Thin separator
                Rectangle()
                    .fill(Theme.teal.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)

                // Row 2: Temp, Wind Chill, Conditions
                HStack(spacing: 0) {
                    ConditionMetricView(
                        symbol: "thermometer.medium",
                        label: "TEMP",
                        value: formatTemp(viewModel.currentConditions.temperatureF),
                        detail: "Fahrenheit",
                        accentColor: tempColor
                    )
                    ConditionDividerView()
                    ConditionMetricView(
                        symbol: "thermometer.snowflake",
                        label: "WIND CHILL",
                        value: formatTemp(viewModel.currentConditions.windChillF),
                        detail: "Feels Like",
                        accentColor: chillColor
                    )
                    ConditionDividerView()
                    if viewModel.selectedLocation.usesNDBC {
                        ConditionMetricView(
                            symbol: "water.waves",
                            label: "WATER TEMP",
                            value: formatTemp(viewModel.currentConditions.waterTemperatureF),
                            detail: "Sea Surface",
                            accentColor: waterTempColor
                        )
                    } else {
                        ConditionMetricView(
                            symbol: conditionsSymbol,
                            label: "CONDITIONS",
                            value: conditionsDescription,
                            detail: conditionsDetail,
                            accentColor: conditionsColor
                        )
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.teal.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current conditions panel")
    }

    // MARK: - Condition Formatting Helpers

    private func formatWindKts(_ kts: Double?) -> String {
        guard let kts else { return "--" }
        return "\(Int(round(kts))) kts"
    }

    private func formatTemp(_ tempF: Double?) -> String {
        guard let tempF else { return "--" }
        return "\(Int(round(tempF)))°F"
    }

    private var windDetail: String {
        guard let dir = viewModel.currentConditions.windCardinal,
              let arrow = viewModel.currentConditions.windArrow else {
            return "Loading…"
        }
        return "\(dir) \(arrow)"
    }

    private var gustDetail: String {
        guard let gustMPH = viewModel.currentConditions.windGustMPH else {
            return "Loading…"
        }
        return "\(Int(round(gustMPH))) mph"
    }

    // MARK: - Conditions (from WeatherSTEM)

    private var conditionsDescription: String {
        viewModel.currentConditions.conditionsPhrase ?? "--"
    }

    private var conditionsSymbol: String {
        guard let code = viewModel.currentConditions.conditionsIconCode else { return "cloud.fill" }
        return WindUtilities.conditionSymbol(iconCode: code)
    }

    private var conditionsDetail: String {
        if let cc = viewModel.currentConditions.cloudCoverPercent {
            return "\(Int(cc))% cloud"
        }
        return "WeatherSTEM"
    }

    private var conditionsColor: Color {
        guard let code = viewModel.currentConditions.conditionsIconCode else { return .white.opacity(0.5) }
        let c = WindUtilities.conditionColor(iconCode: code)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    // MARK: - Condition Colors

    private var windMetricColor: Color {
        guard let kts = viewModel.currentConditions.windSpeedKts else { return Theme.brightGreen }
        return windColor(for: kts)
    }

    private var gustMetricColor: Color {
        guard let kts = viewModel.currentConditions.windGustKts else { return Theme.brightGreen }
        return windColor(for: kts)
    }

    private var tempColor: Color {
        guard let f = viewModel.currentConditions.temperatureF else { return .white }
        if f < 50 { return Color(hex: "64B5F6") }       // Cold blue
        if f < 70 { return Theme.brightGreen }            // Comfortable green
        if f < 85 { return Theme.windYellow }              // Warm yellow
        return Theme.windRed                                // Hot red
    }

    private var chillColor: Color {
        guard let f = viewModel.currentConditions.windChillF else { return .white }
        if f < 40 { return Color(hex: "42A5F5") }
        if f < 55 { return Color(hex: "64B5F6") }
        if f < 70 { return Theme.brightGreen }
        return Theme.windYellow
    }

    private var waterTempColor: Color {
        guard let f = viewModel.currentConditions.waterTemperatureF else { return .white.opacity(0.5) }
        if f < 65 { return Color(hex: "64B5F6") }
        if f < 75 { return Theme.brightGreen }
        if f < 82 { return Theme.windYellow }
        return Theme.windRed
    }

    private var conditionsStatusColor: Color {
        viewModel.weatherSTEMError == nil ? Theme.brightGreen : Theme.windYellow
    }

    private var conditionsStatusLabel: String {
        viewModel.weatherSTEMError == nil ? "LIVE" : "CACHED"
    }

    // MARK: - Wind Tide Horizon Card

    private var windTideHorizonCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wind & Tide Forecast")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ZStack(alignment: .leading) {
                if viewModel.forecastHours.isEmpty {
                    Text("Waiting for data…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .top) {
                            timelineContent
                        }
                        .frame(height: 380)
                        .padding(.horizontal, 16)
                    }
                    .task {
                        // Brief yield to let the ScrollView layout before scrolling
                        try? await Task.sleep(for: .milliseconds(50))
                        withAnimation(.none) {
                            proxy.scrollTo("pastAnchor6h", anchor: .leading)
                        }
                    }
                }

                // Pinned Y-axis tide labels
                tideYAxisLabels
                } // else (data available)
            }

            HStack(spacing: 16) {
                legendDot(color: Theme.brightGreen, label: "<8 kts")
                legendDot(color: Theme.windYellow, label: "8–12 kts")
                legendDot(color: Theme.windRed, label: ">12 kts")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text("Rain")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 6)
        }
        .glassCard(cornerRadius: 18)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Tide Y-Axis Labels (pinned left)

    private var tideYAxisLabels: some View {
        let chartHeight: CGFloat = 230
        let chartTop: CGFloat = 90
        let minTide = viewModel.stats.minTide
        let maxTide = viewModel.stats.maxTide

        // Generate nice round tick values (every 0.5 ft)
        let step = 0.5
        let firstTick = (minTide / step).rounded(.up) * step
        let lastTick = (maxTide / step).rounded(.down) * step
        var ticks: [Double] = []
        var v = firstTick
        while v <= lastTick {
            ticks.append(v)
            v += step
        }

        return VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Semi-transparent backing so labels are readable over the chart
                LinearGradient(
                    colors: [Theme.deepGulf.opacity(0.95), Theme.deepGulf.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 42)

                ForEach(ticks, id: \.self) { tick in
                    let y = tideY(tick, chartTop: chartTop, chartHeight: chartHeight)
                    Text(String(format: tick == tick.rounded() ? "%.0f" : "%.1f", tick))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.teal.opacity(0.55))
                        .position(x: 18, y: y)
                }

                // "ft" unit label at top
                Text("ft")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal.opacity(0.35))
                    .position(x: 18, y: chartTop - 8)
            }
            .frame(width: 42, height: 380)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        let data = viewModel.forecastHours
        let barSpacing: CGFloat = 22
        let totalWidth = CGFloat(data.count) * barSpacing + 40
        let chartHeight: CGFloat = 230
        let chartTop: CGFloat = 90
        let windBarMaxH: CGFloat = 160
        let nowIdx = data.firstIndex(where: { $0.hourOffset == 0 }) ?? 24
        let nowX = 20 + CGFloat(nowIdx) * barSpacing
        let zeroY = tideY(0, chartTop: chartTop, chartHeight: chartHeight)

        return ZStack(alignment: .topLeading) {
            timelineConditionIcons(data: data, barSpacing: barSpacing)
            timelineDaylightBands(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
            timelineSunMarkers(data: data, barSpacing: barSpacing)
            timelineDaySeparators(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
            timelineZeroLine(zeroY: zeroY, chartTop: chartTop, chartHeight: chartHeight, totalWidth: totalWidth)
            tideCurvePath(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
            timelineTideExtrema(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
            timelineWindBars(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight, maxBarH: windBarMaxH)
            timelineNowIndicator(nowX: nowX, chartTop: chartTop, chartHeight: chartHeight)
            timelineScrollAnchors(nowX: nowX, barSpacing: barSpacing, totalWidth: totalWidth)
            timelineTimeLabels(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
        }
        .frame(width: totalWidth, height: 380)
    }

    // MARK: - Timeline Sub-Views

    @ViewBuilder
    private func timelineConditionIcons(data: [ForecastHour], barSpacing: CGFloat) -> some View {
        ForEach(Array(data.enumerated()), id: \.offset) { idx, hour in
            let x = 20 + CGFloat(idx) * barSpacing
            let hourComp = DateUtilities.calendar.component(.hour, from: hour.date)
            if hourComp % 2 == 0 && hour.hourOffset >= 0 {
                let sym = WindUtilities.wmoSymbol(code: hour.weatherCode)
                let rgb = WindUtilities.wmoColor(code: hour.weatherCode)
                Image(systemName: sym)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: Double(rgb.r)/255, green: Double(rgb.g)/255, blue: Double(rgb.b)/255).opacity(0.8))
                    .position(x: x, y: 6)

                if let temp = hour.temperatureF {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: x, y: 20)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineDaylightBands(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        ForEach(Array(ForecastViewModel.computeDaylightRanges(data: data).enumerated()), id: \.offset) { _, range in
            let startX = 20 + CGFloat(range.start) * barSpacing
            let endX = 20 + CGFloat(range.end) * barSpacing
            let width = endX - startX
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "3B7DD8").opacity(0.22),
                            Color(hex: "3B7DD8").opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: chartHeight)
                .position(x: startX + width / 2, y: chartTop + chartHeight / 2)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func timelineSunMarkers(data: [ForecastHour], barSpacing: CGFloat) -> some View {
        ForEach(Array(data.enumerated()), id: \.offset) { idx, hour in
            let x = 20 + CGFloat(idx) * barSpacing
            if hour.isSunrise {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange.opacity(0.8))
                    .position(x: x, y: 42)

                Text(dayOfWeek(hour.date))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.5))
                    .position(x: x, y: 56)
            }
            if hour.isSunset {
                Image(systemName: "moon.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .position(x: x, y: 42)
            }
        }
    }

    @ViewBuilder
    private func timelineDaySeparators(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        ForEach(Array(data.enumerated()), id: \.offset) { idx, hour in
            if hour.isMidnight && idx > 0 {
                let x = 20 + CGFloat(idx) * barSpacing
                Rectangle()
                    .fill(Theme.teal.opacity(0.15))
                    .frame(width: 1, height: chartHeight + 20)
                    .position(x: x, y: chartTop + chartHeight / 2)

                Text(hour.dayLabel)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal.opacity(0.55))
                    .position(x: x, y: 68)
            }
        }
    }

    @ViewBuilder
    private func timelineZeroLine(zeroY: CGFloat, chartTop: CGFloat, chartHeight: CGFloat, totalWidth: CGFloat) -> some View {
        if zeroY >= chartTop && zeroY <= chartTop + chartHeight {
            Path { path in
                path.move(to: CGPoint(x: 0, y: zeroY))
                path.addLine(to: CGPoint(x: totalWidth, y: zeroY))
            }
            .stroke(
                .white.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [8, 5])
            )
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func timelineTideExtrema(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        ForEach(findTideExtrema(data: data), id: \.index) { extremum in
            let x = 20 + CGFloat(extremum.index) * barSpacing
            let curveY = tideY(extremum.tideFt, chartTop: chartTop, chartHeight: chartHeight)
            let color: Color = extremum.isHigh ? Theme.teal.opacity(0.9) : .orange.opacity(0.9)
            let labelY: CGFloat = extremum.isHigh ? chartTop - 6 : chartTop + 10

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .position(x: x, y: curveY)

            Path { path in
                path.move(to: CGPoint(x: x, y: curveY - 3))
                path.addLine(to: CGPoint(x: x, y: labelY + (extremum.isHigh ? 16 : 0)))
            }
            .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))

            VStack(spacing: 0) {
                Text(extremum.isHigh ? "H" : "L")
                    .font(.system(size: 9, weight: .black))
                Text(String(format: "%.1f'", extremum.tideFt))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                Text(extremum.timeLabel)
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(color)
            .position(x: x, y: labelY + 24)
            .accessibilityLabel("\(extremum.isHigh ? "High" : "Low") tide \(String(format: "%.1f", extremum.tideFt)) feet at \(extremum.timeLabel)")
        }
    }

    @ViewBuilder
    private func timelineWindBars(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat, maxBarH: CGFloat) -> some View {
        ForEach(Array(data.enumerated()), id: \.offset) { idx, hour in
            let x = 20 + CGFloat(idx) * barSpacing
            let isPast = hour.hourOffset < 0
            let opacity = isPast ? 0.25 : 1.0

            windBarView(hour: hour, x: x, chartTop: chartTop, chartHeight: chartHeight, maxBarH: maxBarH, opacity: opacity)
        }
    }

    @ViewBuilder
    private func timelineNowIndicator(nowX: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: 1.5, height: chartHeight + 30)
            .position(x: nowX, y: chartTop + chartHeight / 2)
            .opacity(nowPulse ? 1.0 : 0.4)
            .shadow(color: .white.opacity(0.6), radius: 6)

        Text("NOW")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(nowPulse ? 0.9 : 0.4))
            .position(x: nowX, y: chartTop + chartHeight + 20)
    }

    @ViewBuilder
    private func timelineScrollAnchors(nowX: CGFloat, barSpacing: CGFloat, totalWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            let pastX = max(nowX - 6 * barSpacing, 0)
            Color.clear.frame(width: pastX, height: 1)
            Color.clear.frame(width: 1, height: 1).id("pastAnchor6h")
            Color.clear.frame(width: nowX - pastX - 0.5, height: 1)
            Color.clear.frame(width: 1, height: 1).id("nowAnchor")
            Spacer(minLength: 0)
        }
        .frame(width: totalWidth, height: 1)
    }

    @ViewBuilder
    private func timelineTimeLabels(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        ForEach(Array(data.enumerated()), id: \.offset) { idx, hour in
            let x = 20 + CGFloat(idx) * barSpacing
            let isPast = hour.hourOffset < 0
            Text(hour.timeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(isPast ? 0.2 : 0.45))
                .rotationEffect(.degrees(-45))
                .position(x: x, y: chartTop + chartHeight + 14)
        }
    }

    // MARK: - Tide Curve

    // Tide Y position helper — maps a tide value to a Y coordinate.
    // Uses 92% of chart height (was 70%) for a more dramatic curve.
    private func tideY(_ tideFt: Double, chartTop: CGFloat, chartHeight: CGFloat) -> CGFloat {
        let minTide = viewModel.stats.minTide
        let tideRange = viewModel.stats.tideRange
        let normalized = (tideFt - minTide) / tideRange
        return chartTop + chartHeight - normalized * chartHeight * 0.92 - chartHeight * 0.04
    }

    private func tideCurvePath(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> some View {
        return ZStack {
            // Filled area under the curve
            Path { path in
                for (idx, hour) in data.enumerated() {
                    let x = 20 + CGFloat(idx) * barSpacing
                    let y = tideY(hour.tideFt, chartTop: chartTop, chartHeight: chartHeight)
                    if idx == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        let prevX = 20 + CGFloat(idx - 1) * barSpacing
                        let cp1x = prevX + barSpacing * 0.4
                        let cp2x = x - barSpacing * 0.4
                        let prevY = tideY(data[idx - 1].tideFt, chartTop: chartTop, chartHeight: chartHeight)
                        path.addCurve(
                            to: CGPoint(x: x, y: y),
                            control1: CGPoint(x: cp1x, y: prevY),
                            control2: CGPoint(x: cp2x, y: y)
                        )
                    }
                }
                let lastX = 20 + CGFloat(data.count - 1) * barSpacing
                path.addLine(to: CGPoint(x: lastX, y: chartTop + chartHeight))
                path.addLine(to: CGPoint(x: 20, y: chartTop + chartHeight))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Theme.teal.opacity(0.2), Theme.teal.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Outer glow stroke
            tideLine(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
                .stroke(Theme.teal, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.teal.opacity(0.7), radius: 10)
                .shadow(color: Theme.teal.opacity(0.4), radius: 20)

            // Inner bright stroke
            tideLine(data: data, barSpacing: barSpacing, chartTop: chartTop, chartHeight: chartHeight)
                .stroke(Theme.teal.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func tideLine(data: [ForecastHour], barSpacing: CGFloat, chartTop: CGFloat, chartHeight: CGFloat) -> Path {
        Path { path in
            for (idx, hour) in data.enumerated() {
                let x = 20 + CGFloat(idx) * barSpacing
                let y = tideY(hour.tideFt, chartTop: chartTop, chartHeight: chartHeight)
                if idx == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = 20 + CGFloat(idx - 1) * barSpacing
                    let cp1x = prevX + barSpacing * 0.4
                    let cp2x = x - barSpacing * 0.4
                    let prevY = tideY(data[idx - 1].tideFt, chartTop: chartTop, chartHeight: chartHeight)
                    path.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: cp1x, y: prevY),
                        control2: CGPoint(x: cp2x, y: y)
                    )
                }
            }
        }
    }

    // MARK: - Chart Helpers

    private struct TideExtremum {
        let index: Int
        let tideFt: Double
        let isHigh: Bool
        let timeLabel: String
    }

    private func findTideExtrema(data: [ForecastHour]) -> [TideExtremum] {
        guard data.count > 6 else { return [] }
        var extrema: [TideExtremum] = []
        let window = 3

        for i in window..<(data.count - window) {
            let curr = data[i].tideFt
            var isMax = true
            var isMin = true

            for j in (i - window)...(i + window) where j != i {
                if data[j].tideFt >= curr { isMax = false }
                if data[j].tideFt <= curr { isMin = false }
            }

            if isMax || isMin {
                if let last = extrema.last, i - last.index < 5 { continue }
                extrema.append(TideExtremum(
                    index: i, tideFt: curr, isHigh: isMax,
                    timeLabel: data[i].timeLabel
                ))
            }
        }
        return extrema
    }

    /// Short day-of-week string (e.g. "MON", "TUE") for a date.
    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = DateUtilities.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Wind Bar View

    @ViewBuilder
    private func windBarView(hour: ForecastHour, x: CGFloat, chartTop: CGFloat, chartHeight: CGFloat, maxBarH: CGFloat, opacity: Double) -> some View {
        if let windKts = hour.windKts, let windDir = hour.windDir, let windArrow = hour.windArrow {
            let barH = CGFloat(windKts / viewModel.stats.maxWind) * maxBarH
            let barBottom = chartTop + chartHeight - 4
            let barTop = barBottom - barH
            let barColor = windColor(for: windKts)

            VStack(spacing: 1) {
                Text(windArrow)
                    .font(.system(size: 21, weight: .bold))
                Text(windDir)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("\(Int(windKts))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(barColor.opacity(opacity))
            .position(x: x, y: barTop - 30)

            if hour.hasRain {
                Image(systemName: "drop.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.cyan.opacity(0.55 * opacity))
                    .position(x: x, y: barTop - 58)
            }

            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [barColor.opacity(0.9), barColor.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6, height: barH)
                .position(x: x, y: barBottom - barH / 2)
                .opacity(opacity)
        }
    }

}

// MARK: - Red Crab

struct RedCrabView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let red = Color.red
            let darkRed = Color(red: 0.6, green: 0.05, blue: 0.05)
            let lw: CGFloat = max(w * 0.016, 0.6)

            // --- Body (oval carapace) ---
            let bodyRect = CGRect(x: w * 0.22, y: h * 0.32, width: w * 0.56, height: h * 0.34)
            context.fill(Path(ellipseIn: bodyRect), with: .color(red))
            // Shell highlight
            let highlightRect = CGRect(x: w * 0.32, y: h * 0.36, width: w * 0.36, height: h * 0.18)
            context.fill(Path(ellipseIn: highlightRect), with: .color(darkRed.opacity(0.4)))

            // --- Eyes on stalks ---
            // Left eye stalk
            var leftStalk = Path()
            leftStalk.move(to: CGPoint(x: w * 0.36, y: h * 0.35))
            leftStalk.addLine(to: CGPoint(x: w * 0.30, y: h * 0.18))
            context.stroke(leftStalk, with: .color(red), lineWidth: lw * 2.5)
            // Left eyeball
            let leftEyeRect = CGRect(x: w * 0.26, y: h * 0.12, width: w * 0.09, height: h * 0.09)
            context.fill(Path(ellipseIn: leftEyeRect), with: .color(red))
            let leftPupil = CGRect(x: w * 0.29, y: h * 0.14, width: w * 0.04, height: h * 0.05)
            context.fill(Path(ellipseIn: leftPupil), with: .color(Color(white: 0.1)))

            // Right eye stalk
            var rightStalk = Path()
            rightStalk.move(to: CGPoint(x: w * 0.64, y: h * 0.35))
            rightStalk.addLine(to: CGPoint(x: w * 0.70, y: h * 0.18))
            context.stroke(rightStalk, with: .color(red), lineWidth: lw * 2.5)
            // Right eyeball
            let rightEyeRect = CGRect(x: w * 0.66, y: h * 0.12, width: w * 0.09, height: h * 0.09)
            context.fill(Path(ellipseIn: rightEyeRect), with: .color(red))
            let rightPupil = CGRect(x: w * 0.68, y: h * 0.14, width: w * 0.04, height: h * 0.05)
            context.fill(Path(ellipseIn: rightPupil), with: .color(Color(white: 0.1)))

            // --- Claws ---
            // Left claw arm
            var leftArm = Path()
            leftArm.move(to: CGPoint(x: w * 0.24, y: h * 0.42))
            leftArm.addCurve(to: CGPoint(x: w * 0.06, y: h * 0.28),
                             control1: CGPoint(x: w * 0.16, y: h * 0.38),
                             control2: CGPoint(x: w * 0.08, y: h * 0.34))
            context.stroke(leftArm, with: .color(red), lineWidth: lw * 3)
            // Left pincer top
            var leftPincerTop = Path()
            leftPincerTop.move(to: CGPoint(x: w * 0.06, y: h * 0.28))
            leftPincerTop.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.18),
                                   control1: CGPoint(x: w * 0.03, y: h * 0.24),
                                   control2: CGPoint(x: w * 0.00, y: h * 0.20))
            context.stroke(leftPincerTop, with: .color(red), lineWidth: lw * 2.5)
            // Left pincer bottom
            var leftPincerBot = Path()
            leftPincerBot.move(to: CGPoint(x: w * 0.06, y: h * 0.28))
            leftPincerBot.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.34),
                                   control1: CGPoint(x: w * 0.03, y: h * 0.30),
                                   control2: CGPoint(x: w * 0.00, y: h * 0.33))
            context.stroke(leftPincerBot, with: .color(red), lineWidth: lw * 2.5)

            // Right claw arm
            var rightArm = Path()
            rightArm.move(to: CGPoint(x: w * 0.76, y: h * 0.42))
            rightArm.addCurve(to: CGPoint(x: w * 0.94, y: h * 0.28),
                              control1: CGPoint(x: w * 0.84, y: h * 0.38),
                              control2: CGPoint(x: w * 0.92, y: h * 0.34))
            context.stroke(rightArm, with: .color(red), lineWidth: lw * 3)
            // Right pincer top
            var rightPincerTop = Path()
            rightPincerTop.move(to: CGPoint(x: w * 0.94, y: h * 0.28))
            rightPincerTop.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.18),
                                    control1: CGPoint(x: w * 0.97, y: h * 0.24),
                                    control2: CGPoint(x: w * 1.00, y: h * 0.20))
            context.stroke(rightPincerTop, with: .color(red), lineWidth: lw * 2.5)
            // Right pincer bottom
            var rightPincerBot = Path()
            rightPincerBot.move(to: CGPoint(x: w * 0.94, y: h * 0.28))
            rightPincerBot.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.34),
                                    control1: CGPoint(x: w * 0.97, y: h * 0.30),
                                    control2: CGPoint(x: w * 1.00, y: h * 0.33))
            context.stroke(rightPincerBot, with: .color(red), lineWidth: lw * 2.5)

            // --- Legs (4 per side) ---
            let legAngles: [(startY: CGFloat, endX: CGFloat, endY: CGFloat)] = [
                (0.50, 0.04, 0.56),
                (0.55, 0.06, 0.68),
                (0.58, 0.10, 0.76),
                (0.60, 0.16, 0.82),
            ]
            for leg in legAngles {
                // Left legs
                var leftLeg = Path()
                leftLeg.move(to: CGPoint(x: w * 0.26, y: h * leg.startY))
                leftLeg.addLine(to: CGPoint(x: w * leg.endX, y: h * leg.endY))
                context.stroke(leftLeg, with: .color(red), lineWidth: lw * 1.8)
                // Right legs (mirrored)
                var rightLeg = Path()
                rightLeg.move(to: CGPoint(x: w * 0.74, y: h * leg.startY))
                rightLeg.addLine(to: CGPoint(x: w * (1.0 - leg.endX), y: h * leg.endY))
                context.stroke(rightLeg, with: .color(red), lineWidth: lw * 1.8)
            }

            // --- Mouth ---
            var mouth = Path()
            mouth.move(to: CGPoint(x: w * 0.42, y: h * 0.58))
            mouth.addCurve(to: CGPoint(x: w * 0.58, y: h * 0.58),
                           control1: CGPoint(x: w * 0.46, y: h * 0.62),
                           control2: CGPoint(x: w * 0.54, y: h * 0.62))
            context.stroke(mouth, with: .color(darkRed), lineWidth: lw * 1.2)
        }
        .accessibilityLabel("Red crab")
    }
}

// MARK: - Fisherizer Tab Icon

/// A composite tab icon showing a fish with a small clock overlay.
struct FisherizerTabIcon: View {
    var body: some View {
        Image(systemName: "fish.fill")
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .background(
                        Circle()
                            .fill(.background)
                            .padding(-1)
                    )
                    .offset(x: 2, y: 2)
            }
    }
}

// MARK: - Preview

#Preview {
    ContentView(viewModel: .preview())
        .preferredColorScheme(.dark)
}
