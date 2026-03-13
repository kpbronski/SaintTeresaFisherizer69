// HRRRTimeSlider.swift — Saint Teresa Fisherizer 69
//
// HRRR REFD forecast time slider. +18 hours in 15-minute steps (73 frames).
// Frame format: F0000 (now) through F1080 (+18h).

import SwiftUI
import Combine

// MARK: - HRRR Time Slider

struct HRRRTimeSlider: View {

    @Binding var hrrrFrameIndex: Int
    @Binding var isPlaying: Bool

    /// 73 frames: F0000, F0015, F0030, ... F1080 (0 to +18h in 15-min steps)
    private let frameCount = 73
    private let stepMinutes = 15

    @State private var frameIndex: Double = 0   // start at +0h (now)

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // dBZ color bar (same scale as NEXRAD — identical product)
            dbzColorBar
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // Label row
            HStack {
                Text(forecastLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.orange)
                    Text("HRRR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.orange)
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
                .accessibilityLabel("Step back 15 minutes")

                // Play / Pause
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(isPlaying ? "Pause forecast loop" : "Play forecast loop")

                // Step forward
                Button {
                    stepForward()
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Step forward 15 minutes")

                // Slider
                Slider(value: $frameIndex, in: 0...Double(frameCount - 1), step: 1) { editing in
                    if !editing {
                        updateFrame()
                    }
                }
                .tint(.orange)
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
                        .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
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

    private var dbzLabels: [String] { ["5", "20", "35", "45", "55", "65+"] }

    private struct DBZEntry: Hashable {
        let label: String
        let color: Color
    }

    private var dbzColors: [DBZEntry] {
        [
            DBZEntry(label: "5",  color: Color(red: 0.0, green: 0.93, blue: 0.93)),
            DBZEntry(label: "15", color: Color(red: 0.0, green: 0.63, blue: 0.0)),
            DBZEntry(label: "20", color: Color(red: 0.0, green: 0.85, blue: 0.0)),
            DBZEntry(label: "30", color: Color(red: 1.0, green: 1.0, blue: 0.0)),
            DBZEntry(label: "35", color: Color(red: 1.0, green: 0.65, blue: 0.0)),
            DBZEntry(label: "40", color: Color(red: 1.0, green: 0.0, blue: 0.0)),
            DBZEntry(label: "45", color: Color(red: 0.8, green: 0.0, blue: 0.0)),
            DBZEntry(label: "50", color: Color(red: 1.0, green: 0.0, blue: 1.0)),
            DBZEntry(label: "55", color: Color(red: 0.6, green: 0.0, blue: 0.6)),
            DBZEntry(label: "65", color: Color(red: 1.0, green: 1.0, blue: 1.0)),
        ]
    }

    // MARK: - Playback

    private var playbackTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    }

    private func stepForward() {
        let next = Int(frameIndex) + 1
        frameIndex = next >= frameCount ? 0 : Double(next)
        updateFrame()
    }

    private func stepBack() {
        isPlaying = false
        let prev = Int(frameIndex) - 1
        frameIndex = prev < 0 ? Double(frameCount - 1) : Double(prev)
        updateFrame()
    }

    // MARK: - Frame Update

    private func updateFrame() {
        hrrrFrameIndex = Int(frameIndex)
    }

    private var forecastLabel: String {
        let idx = Int(frameIndex)
        let totalMinutes = idx * stepMinutes

        if totalMinutes == 0 {
            return "Now (+0h)"
        }

        let hours = totalMinutes / 60
        let mins = totalMinutes % 60

        // Calculate target UTC time
        let targetDate = Date().addingTimeInterval(TimeInterval(totalMinutes * 60))
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "HH:mm"
        let utcStr = fmt.string(from: targetDate)

        if mins == 0 {
            return "\(utcStr) UTC • +\(hours)h"
        } else {
            return "\(utcStr) UTC • +\(hours)h\(mins)m"
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            HRRRTimeSlider(
                hrrrFrameIndex: .constant(0),
                isPlaying: .constant(false)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }
    .preferredColorScheme(.dark)
}
