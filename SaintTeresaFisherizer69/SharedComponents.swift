import SwiftUI

// MARK: - Shared Ocean Background View

/// Single shared background with animated wave Canvas.
/// Used by all tabs to avoid 5 duplicate animation loops.
struct OceanBackgroundView: View {
    var body: some View {
        ZStack {
            Theme.deepGulf.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: false)) { timeline in
                Canvas { context, size in
                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                    let time = seconds.truncatingRemainder(dividingBy: 12) / 12 * .pi * 2
                    for i in 0..<5 {
                        let y = size.height * (0.2 + CGFloat(i) * 0.18)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        for x in stride(from: 0, to: size.width, by: 4) {
                            let wave = sin(x / 120 + time + CGFloat(i) * 1.2) * 8
                            path.addLine(to: CGPoint(x: x, y: y + wave))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: y + 40))
                        path.addLine(to: CGPoint(x: 0, y: y + 40))
                        path.closeSubpath()
                        context.fill(path, with: .color(Theme.teal.opacity(0.012 + Double(i) * 0.003)))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Location Picker (shared across Wind & Tide + Fisherizer tabs)

struct LocationPickerView: View {
    @Bindable var viewModel: ForecastViewModel

    var body: some View {
        Menu {
            ForEach(FishingLocation.allCases) { location in
                Button {
                    viewModel.selectedLocation = location
                } label: {
                    Label {
                        Text(location.displayName)
                    } icon: {
                        if location == viewModel.selectedLocation {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedLocation.sfSymbol)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.identity)
                Text(viewModel.selectedLocation.displayName.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1.5)
                    .contentTransition(.identity)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.cardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(Theme.gold.opacity(0.3), lineWidth: 0.5)
            )
        }
        .accessibilityLabel("Location selector, currently \(viewModel.selectedLocation.displayName)")
    }
}

// MARK: - Condition Metric Cell (shared)

struct ConditionMetricView: View {
    let symbol: String
    let label: String
    let value: String
    var detail: String = ""
    let accentColor: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.7))
                Text(label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)
            }

            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .shadow(color: accentColor.opacity(0.4), radius: 6)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }
}

// MARK: - Condition Divider (shared)

struct ConditionDividerView: View {
    var height: CGFloat = 44

    var body: some View {
        Rectangle()
            .fill(Theme.teal.opacity(0.12))
            .frame(width: 0.5, height: height)
    }
}
