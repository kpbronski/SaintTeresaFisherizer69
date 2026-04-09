import UIKit
import SwiftUI

// MARK: - Beaufort Inshore Color Ramp

/// Single source of truth for the wind speed color ramp.
/// Used by both the map heatmap and any future chart/legend UI.
/// Do not modify these values without explicit Kevin approval — they are
/// the cross-app standard shared with Boatclaw.
enum BeaufortInshoreRamp {

    // MARK: - Ramp Stops (knots → color)

    /// | Knots | Beaufort | Color          | Semantic       |
    /// |-------|----------|----------------|----------------|
    /// | 0–3   | 0–1      | #1A1B3A        | Glass calm     |
    /// | 3–7   | 2        | #2D3D6B        | Light air      |
    /// | 7–11  | 3        | #1F6B7A (teal) | Gentle breeze  |
    /// | 11–15 | 4        | #2EA88A        | Moderate       |
    /// | 15–19 | 5        | #D4C04A (yel)  | Fresh — caution|
    /// | 19–24 | 6        | #E08A2E (org)  | Strong — gnarly|
    /// | 24+   | 7+       | #C8442E (red)  | Stay home      |

    struct RampStop {
        let knots: Float
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    /// Saturation bumped +15% from original spec hex values for map legibility.
    /// Original values: 1A1B3A, 2D3D6B, 1F6B7A, 2EA88A, D4C04A, E08A2E, C8442E
    static let stops: [RampStop] = [
        RampStop(knots: 0,  r: 0x18, g: 0x19, b: 0x3C),  // Glass calm
        RampStop(knots: 3,  r: 0x28, g: 0x3B, b: 0x70),  // Light air
        RampStop(knots: 7,  r: 0x18, g: 0x70, b: 0x81),  // Gentle breeze
        RampStop(knots: 11, r: 0x25, g: 0xB1, b: 0x8F),  // Moderate
        RampStop(knots: 15, r: 0xDE, g: 0xC7, b: 0x40),  // Fresh — caution
        RampStop(knots: 19, r: 0xED, g: 0x8A, b: 0x21),  // Strong — gnarly
        RampStop(knots: 24, r: 0xD4, g: 0x3C, b: 0x22),  // Stay home
    ]

    // MARK: - Interpolated Color Lookup

    /// Returns an interpolated (r, g, b) tuple for a given wind speed in knots.
    static func color(forKnots knots: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let k = max(0, knots)

        // Below first stop
        if k <= stops[0].knots {
            return (stops[0].r, stops[0].g, stops[0].b)
        }

        // Above last stop
        if k >= stops[stops.count - 1].knots {
            let last = stops[stops.count - 1]
            return (last.r, last.g, last.b)
        }

        // Find bracketing stops and interpolate
        for i in 0..<(stops.count - 1) {
            let lo = stops[i]
            let hi = stops[i + 1]
            if k >= lo.knots && k <= hi.knots {
                let t = (k - lo.knots) / (hi.knots - lo.knots)
                let r = UInt8(Float(lo.r) + t * (Float(hi.r) - Float(lo.r)))
                let g = UInt8(Float(lo.g) + t * (Float(hi.g) - Float(lo.g)))
                let b = UInt8(Float(lo.b) + t * (Float(hi.b) - Float(lo.b)))
                return (r, g, b)
            }
        }

        let last = stops[stops.count - 1]
        return (last.r, last.g, last.b)
    }

    /// SwiftUI Color version for use in badges/legends.
    static func swiftUIColor(forKnots knots: Float) -> Color {
        let c = color(forKnots: knots)
        return Color(
            red: Double(c.r) / 255,
            green: Double(c.g) / 255,
            blue: Double(c.b) / 255
        )
    }

    // MARK: - Heatmap Image Generation

    /// Renders a `WindFieldSnapshot` into a `UIImage` suitable for Mapbox `ImageSource`.
    /// The image is gridWidth x gridHeight pixels with RGBA data; Mapbox's bilinear
    /// resampling smooths it when rendering at screen resolution.
    static func heatmapImage(from snapshot: WindFieldSnapshot, alpha: UInt8 = 70) -> UIImage? {
        let w = snapshot.gridWidth
        let h = snapshot.gridHeight
        let count = w * h

        guard snapshot.sustainedKnots.count >= count else { return nil }

        // Build raw RGBA pixel data
        var pixels = [UInt8](repeating: 0, count: count * 4)

        for i in 0..<count {
            // Grid is row-major, top-to-bottom in data, but UIImage is also
            // top-to-bottom, so we flip vertically so south is at bottom.
            let row = i / w
            let col = i % w
            let flippedRow = (h - 1) - row
            let srcIdx = flippedRow * w + col

            let knots = snapshot.sustainedKnots[srcIdx]
            let c = color(forKnots: knots)

            let px = i * 4
            pixels[px]     = c.r
            pixels[px + 1] = c.g
            pixels[px + 2] = c.b
            pixels[px + 3] = alpha
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
