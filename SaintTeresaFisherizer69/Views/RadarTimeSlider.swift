// RadarTimeSlider.swift — Saint Teresa Fisherizer 69
//
// 120-minute NEXRAD time slider with play/pause, scrubber, step buttons,
// inline dBZ color bar, and Go Live button.

import SwiftUI

// MARK: - Radar Time Slider

struct RadarTimeSlider: View {

    @Binding var nexradFrameIndex: Int
    @Binding var isPlaying: Bool

    /// Total frames covering 120 minutes at 5-min intervals (index 0 = oldest, 23 = live)
    private let frameCount = 24
    private let stepMinutes = 5

    @State private var frameIndex: Double = 23   // start live

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // dBZ color bar
            dbzColorBar
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // Time label
            HStack {
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if Int(frameIndex) < frameCount - 1 {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            frameIndex = Double(frameCount - 1)
                            isPlaying = false
                            updateFrame()
                        }
                    } label: {
                        Text("GO LIVE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red.opacity(0.8)))
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Scrubber + controls
            HStack(spacing: 12) {
                // Step back
                Button {
                    stepBack()
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Step back 5 minutes")

                // Play / Pause
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(isPlaying ? "Pause radar loop" : "Play radar loop")

                // Step forward
                Button {
                    stepForward()
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Step forward 5 minutes")

                // Slider
                Slider(value: $frameIndex, in: 0...Double(frameCount - 1), step: 1) { editing in
                    if !editing {
                        updateFrame()
                    }
                }
                .tint(Theme.teal)
                .onChange(of: frameIndex) {
                    updateFrame()
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.deepGulf.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.teal.opacity(0.15), lineWidth: 0.5)
                )
        )
        .onReceive(playbackTimer) { _ in
            guard isPlaying else { return }
            stepForward()
        }
    }

    // MARK: - dBZ Color Bar

    private var dbzColorBar: some View {
        VStack(spacing: 2) {
            // Gradient strip
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(dbzColors, id: \.label) { entry in
                        entry.color
                            .frame(width: geo.size.width / CGFloat(dbzColors.count))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: 6)

            // Labels
            HStack {
                ForEach(dbzLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    if label != dbzLabels.last {
                        Spacer()
                    }
                }
            }
        }
    }

    private var dbzLabels: [String] {
        ["5", "20", "35", "45", "55", "65+"]
    }

    private struct DBZEntry: Hashable {
        let label: String
        let color: Color
    }

    private var dbzColors: [DBZEntry] {
        [
            DBZEntry(label: "5",  color: Color(red: 0.0, green: 0.93, blue: 0.93)),   // light cyan
            DBZEntry(label: "15", color: Color(red: 0.0, green: 0.63, blue: 0.0)),     // dark green
            DBZEntry(label: "20", color: Color(red: 0.0, green: 0.85, blue: 0.0)),     // green
            DBZEntry(label: "30", color: Color(red: 1.0, green: 1.0, blue: 0.0)),      // yellow
            DBZEntry(label: "35", color: Color(red: 1.0, green: 0.65, blue: 0.0)),     // orange
            DBZEntry(label: "40", color: Color(red: 1.0, green: 0.0, blue: 0.0)),      // red
            DBZEntry(label: "45", color: Color(red: 0.8, green: 0.0, blue: 0.0)),      // dark red
            DBZEntry(label: "50", color: Color(red: 1.0, green: 0.0, blue: 1.0)),      // magenta
            DBZEntry(label: "55", color: Color(red: 0.6, green: 0.0, blue: 0.6)),      // purple
            DBZEntry(label: "65", color: Color(red: 1.0, green: 1.0, blue: 1.0)),      // white
        ]
    }

    // MARK: - Playback

    private var playbackTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    }

    private func stepForward() {
        let next = Int(frameIndex) + 1
        if next >= frameCount {
            frameIndex = 0
        } else {
            frameIndex = Double(next)
        }
        updateFrame()
    }

    private func stepBack() {
        isPlaying = false
        let prev = Int(frameIndex) - 1
        if prev < 0 {
            frameIndex = Double(frameCount - 1)
        } else {
            frameIndex = Double(prev)
        }
        updateFrame()
    }

    // MARK: - Frame Update

    private func updateFrame() {
        nexradFrameIndex = Int(frameIndex)
    }

    private var timeLabel: String {
        let idx = Int(frameIndex)
        if idx >= frameCount - 1 {
            return "Now"
        }

        let minutesAgo = (frameCount - 1 - idx) * stepMinutes

        // Calculate the actual UTC time
        let date = Date().addingTimeInterval(TimeInterval(-minutesAgo * 60))
        let cal = Calendar.current
        var comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let minute = comps.minute ?? 0
        comps.minute = (minute / 5) * 5
        comps.second = 0

        guard let rounded = cal.date(from: comps) else { return "\(minutesAgo)m ago" }

        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "HH:mm"
        let utcStr = fmt.string(from: rounded)

        return "\(utcStr) UTC • \(minutesAgo)m ago"
    }
}

import Combine

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            RadarTimeSlider(
                nexradFrameIndex: .constant(23),
                isPlaying: .constant(false)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }
    .preferredColorScheme(.dark)
}
