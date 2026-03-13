import SwiftUI

// MARK: - Fishing Window Model

struct FishingWindow: Identifiable {
    let hours: [ForecastHour]

    /// Stable identity based on the window's start time.
    var id: Date { hours.first?.date ?? .distantPast }
    var startDate: Date { hours.first?.date ?? Date() }
    var endDate: Date {
        guard let last = hours.last else { return Date() }
        return DateUtilities.calendar.date(byAdding: .hour, value: 1, to: last.date) ?? last.date
    }
    var durationHours: Int { hours.count }

    var averageWindKts: Double {
        let winds = hours.compactMap(\.windKts)
        guard !winds.isEmpty else { return 0 }
        return winds.reduce(0, +) / Double(winds.count)
    }

    var tempHighF: Double {
        hours.compactMap(\.temperatureF).max() ?? 0
    }

    var tempLowF: Double {
        hours.compactMap(\.temperatureF).min() ?? 0
    }
}

// MARK: - Formatters

private let windowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let windowTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let monthYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM yyyy"
    f.locale = Locale(identifier: "en_US")
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let shortMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM"
    f.locale = Locale(identifier: "en_US")
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let yearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy"
    f.locale = Locale(identifier: "en_US")
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

// MARK: - Fisherizer View

struct FisherizerView: View {
    @Bindable var viewModel: ForecastViewModel

    var body: some View {
        ZStack {
            backgroundLayer

            if viewModel.isLoading && viewModel.forecastHours.isEmpty {
                loadingView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection

                        if let error = viewModel.errorMessage {
                            errorBanner(message: error)
                        }

                        filterControls

                        fishingCalendar

                        windowSection(
                            icon: viewModel.requireIncomingTide ? "water.waves" : "wind",
                            emoji: viewModel.requireIncomingTide ? "\u{1F30A}\u{1F4A8}" : "\u{1F3A3}",
                            title: viewModel.requireIncomingTide ? "INCOMING TIDE + CALM" : "FISHING WINDOWS",
                            subtitle: windowSubtitle,
                            accentColor: Theme.brightGreen,
                            windows: viewModel.fishingWindows
                        )
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
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        OceanBackgroundView()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Dispatcher")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Use the filters to find best times to get that boat in the water")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.35))

            LocationPickerView(viewModel: viewModel)

            if let last = viewModel.lastUpdated {
                let seconds = Int(Date().timeIntervalSince(last))
                let label = seconds < 60 ? "Updated just now" : "Updated \(seconds / 60) min ago"
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Filter Controls

    private var windowSubtitle: String {
        var parts: [String] = []
        if viewModel.requireIncomingTide { parts.append("Tide rising") }
        parts.append("Wind < \(Int(viewModel.windThresholdKts)) kts")
        parts.append("\(viewModel.minimumWindowHours)+ hrs")
        parts.append("Daytime")
        return parts.joined(separator: " · ")
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.teal)
                Text("FILTERS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.teal)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            Rectangle()
                .fill(Theme.teal.opacity(0.2))
                .frame(height: 0.5)

            // Wind threshold slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "wind")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(windColor(for: viewModel.windThresholdKts))
                    Text("MAX WIND")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)
                    Spacer()
                    Text("\(Int(viewModel.windThresholdKts)) kts")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(windColor(for: viewModel.windThresholdKts))
                        .contentTransition(.numericText())
                }

                Slider(
                    value: $viewModel.windThresholdKts,
                    in: 3...25,
                    step: 1
                )
                .tint(windColor(for: viewModel.windThresholdKts))
                .accessibilityLabel("Maximum wind speed filter")
                .accessibilityValue("\(Int(viewModel.windThresholdKts)) knots")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Rectangle()
                .fill(Theme.teal.opacity(0.1))
                .frame(height: 0.5)
                .padding(.top, 8)

            // Minimum window hours slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text("MIN WINDOW")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)
                    Spacer()
                    Text("\(viewModel.minimumWindowHours) hrs")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                        .contentTransition(.numericText())
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.minimumWindowHours) },
                        set: { viewModel.minimumWindowHours = Int($0) }
                    ),
                    in: 1...12,
                    step: 1
                )
                .tint(Theme.gold)
                .accessibilityLabel("Minimum fishing window duration")
                .accessibilityValue("\(viewModel.minimumWindowHours) hours")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Rectangle()
                .fill(Theme.teal.opacity(0.1))
                .frame(height: 0.5)
                .padding(.top, 8)

            // Incoming tide toggle
            HStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(viewModel.requireIncomingTide ? Theme.brightGreen : .white.opacity(0.3))
                Text("INCOMING TIDE ONLY")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(viewModel.requireIncomingTide ? .white.opacity(0.8) : .white.opacity(0.4))
                    .tracking(0.5)
                Spacer()
                Toggle("", isOn: $viewModel.requireIncomingTide)
                    .labelsHidden()
                    .tint(Theme.brightGreen)
                    .accessibilityLabel("Filter to incoming tide only")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.teal.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Fishing Calendar

    /// Encoded as yyyyMMdd ints for reliable Set membership (DateComponents equality is fragile).
    private var highlightedDays: Set<Int> {
        var days = Set<Int>()
        let cal = DateUtilities.calendar
        for window in viewModel.fishingWindows {
            for hour in window.hours {
                let y = cal.component(.year, from: hour.date)
                let m = cal.component(.month, from: hour.date)
                let d = cal.component(.day, from: hour.date)
                days.insert(y * 10000 + m * 100 + d)
            }
        }
        return days
    }

    /// Helper to encode a calendar day as an Int key matching highlightedDays.
    private static func dayKey(year: Int, month: Int, day: Int) -> Int {
        year * 10000 + month * 100 + day
    }

    /// The months that the forecast spans (usually 1-2).
    private var forecastMonths: [Date] {
        let cal = DateUtilities.calendar
        let now = Date()
        guard let end = cal.date(byAdding: .day, value: 15, to: now) else { return [now] }

        let startMonth = cal.dateComponents([.year, .month], from: now)
        let endMonth = cal.dateComponents([.year, .month], from: end)

        var months: [Date] = []
        if let first = cal.date(from: startMonth) {
            months.append(first)
        }
        if startMonth != endMonth, let second = cal.date(from: endMonth) {
            months.append(second)
        }
        return months
    }

    /// Build a readable month label like "FEBRUARY 2026" or "FEB – MAR 2026".
    private var calendarHeaderLabel: String {
        let months = forecastMonths
        guard let first = months.first else { return "FORECAST CALENDAR" }

        if months.count > 1, let second = months.last {
            let firstShort = shortMonthFormatter.string(from: first).uppercased()
            let secondShort = shortMonthFormatter.string(from: second).uppercased()
            let firstYear = yearFormatter.string(from: first)
            let secondYear = yearFormatter.string(from: second)
            if firstYear == secondYear {
                return "\(firstShort) \u{2013} \(secondShort) \(firstYear)"
            }
            return "\(firstShort) \(firstYear) \u{2013} \(secondShort) \(secondYear)"
        }
        return monthYearFormatter.string(from: first).uppercased()
    }

    private var fishingCalendar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.brightGreen)
                Text(verbatim: calendarHeaderLabel)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.brightGreen)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            Rectangle()
                .fill(Theme.brightGreen.opacity(0.2))
                .frame(height: 0.5)

            // Month grids
            let highlighted = highlightedDays
            ForEach(forecastMonths, id: \.self) { monthDate in
                monthGrid(for: monthDate, highlighted: highlighted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Legend
            HStack(spacing: 12) {
                legendDot(color: Theme.brightGreen, label: "Fishing Window")
                legendDot(color: .white.opacity(0.2), label: "Today")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .glassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.brightGreen.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func monthGrid(for monthDate: Date, highlighted: Set<Int>) -> some View {
        let cal = DateUtilities.calendar
        let year = cal.component(.year, from: monthDate)
        let month = cal.component(.month, from: monthDate)
        let todayComps = cal.dateComponents([.year, .month, .day], from: Date())
        let todayKey = Self.dayKey(year: todayComps.year!, month: todayComps.month!, day: todayComps.day!)

        // Month/year label via DateFormatter (locale-safe)
        let monthLabel = monthYearFormatter.string(from: monthDate)

        // First day of month & how many days
        let range = cal.range(of: .day, in: .month, for: monthDate)!
        let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun
        let offset = firstWeekday - cal.firstWeekday

        // Build grid rows
        let daySymbols = cal.veryShortWeekdaySymbols

        // Determine which days are within the forecast range (don't grey-out)
        let now = Date()
        let forecastEnd = cal.date(byAdding: .day, value: 15, to: now) ?? now
        let todayStart = cal.startOfDay(for: now)

        return VStack(spacing: 4) {
            // Month label
            Text(verbatim: monthLabel)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .padding(.bottom, 2)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(daySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells in a 6-row grid
            let totalSlots = offset + range.count
            let rows = (totalSlots + 6) / 7

            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let slot = row * 7 + col
                        let day = slot - offset + 1

                        if day >= 1 && day <= range.count {
                            let key = Self.dayKey(year: year, month: month, day: day)
                            let isHighlighted = highlighted.contains(key)
                            let isToday = key == todayKey
                            let dayDate = cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date.distantPast
                            let inForecast = dayDate >= todayStart && dayDate <= forecastEnd

                            dayCell(
                                day: day,
                                isHighlighted: isHighlighted,
                                isToday: isToday,
                                inForecast: inForecast
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(day: Int, isHighlighted: Bool, isToday: Bool, inForecast: Bool) -> some View {
        Text("\(day)")
            .font(.system(size: 13, weight: isHighlighted ? .bold : .medium, design: .rounded))
            .foregroundStyle(
                isHighlighted ? .white :
                inForecast ? .white.opacity(0.6) :
                .white.opacity(0.2)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                Group {
                    if isHighlighted {
                        Circle()
                            .fill(Theme.brightGreen.opacity(0.35))
                            .frame(width: 28, height: 28)
                    } else if isToday {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 28, height: 28)
                    }
                }
            )
            .overlay(
                Group {
                    if isToday {
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                            .frame(width: 28, height: 28)
                    }
                }
            )
            .accessibilityLabel(
                isHighlighted ? "Day \(day), fishing window available" :
                isToday ? "Day \(day), today" :
                "Day \(day)"
            )
    }

    // MARK: - Loading

    @State private var crabSpin: Double = 0

    private var loadingView: some View {
        VStack(spacing: 16) {
            Text("\u{1F980}")
                .font(.system(size: 48))
                .rotationEffect(.degrees(crabSpin))
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        crabSpin = 360
                    }
                }
            Text("Hold onto your butts.")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityLabel("Loading fishing window data")
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
    }

    // MARK: - Window Section

    @ViewBuilder
    private func windowSection(
        icon: String,
        emoji: String,
        title: String,
        subtitle: String,
        accentColor: Color,
        windows: [FishingWindow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(emoji)
                        .font(.system(size: 16))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(title)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .tracking(1.2)
                    Spacer()
                    Text("\(Text("\(windows.count)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(accentColor)) \(Text("found").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4)))")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 5)

                Rectangle()
                    .fill(accentColor.opacity(0.2))
                    .frame(height: 0.5)

                Text(subtitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .glassCard(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accentColor.opacity(0.2), lineWidth: 0.5)
            )

            // Window cards
            if windows.isEmpty {
                emptyCard(accentColor: accentColor)
            } else {
                ForEach(windows) { window in
                    windowCard(window: window, accentColor: accentColor)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyCard(accentColor: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor.opacity(0.4))
            Text("No qualifying windows in the forecast")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Window Card

    private func windowCard(window: FishingWindow, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: date · time range · duration badge
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(windowDateFormatter.string(from: window.startDate))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("\u{00B7}")
                    .foregroundStyle(.white.opacity(0.3))

                Text(timeRange(for: window))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor)

                Spacer()

                // Duration badge
                Text("\(window.durationHours) HRS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Separator
            Rectangle()
                .fill(accentColor.opacity(0.12))
                .frame(height: 0.5)

            // Metric row: 3 columns
            HStack(spacing: 0) {
                ConditionMetricView(
                    symbol: "wind",
                    label: "AVG WIND",
                    value: "\(Int(round(window.averageWindKts))) kts",
                    accentColor: windColor(for: window.averageWindKts)
                )

                windowDivider(accentColor: accentColor)

                ConditionMetricView(
                    symbol: "thermometer.medium",
                    label: "TEMP",
                    value: "\(Int(round(window.tempLowF)))\u{00B0}\u{2013}\(Int(round(window.tempHighF)))\u{00B0}F",
                    accentColor: tempRangeColor(low: window.tempLowF, high: window.tempHighF)
                )

                windowDivider(accentColor: accentColor)

                ConditionMetricView(
                    symbol: "clock",
                    label: "DURATION",
                    value: "\(window.durationHours) hrs",
                    accentColor: accentColor
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accentColor.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Fishing window: \(windowDateFormatter.string(from: window.startDate)), "
            + "\(timeRange(for: window)), "
            + "\(window.durationHours) hours, "
            + "average wind \(Int(round(window.averageWindKts))) knots"
        )
    }

    private func windowDivider(accentColor: Color) -> some View {
        ConditionDividerView(height: 38)
    }

    // MARK: - Formatting Helpers

    private func timeRange(for window: FishingWindow) -> String {
        "\(windowTimeFormatter.string(from: window.startDate)) \u{2013} \(windowTimeFormatter.string(from: window.endDate))"
    }

    private func tempRangeColor(low: Double, high: Double) -> Color {
        let avg = (low + high) / 2
        if avg < 50 { return Color(hex: "64B5F6") }
        if avg < 70 { return Theme.brightGreen }
        if avg < 85 { return Theme.windYellow }
        return Theme.windRed
    }

}

// MARK: - Preview

#Preview {
    FisherizerView(viewModel: .preview())
        .preferredColorScheme(.dark)
}
