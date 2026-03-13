import SwiftUI

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme

enum Theme {
    static let deepGulf = Color(hex: "0A1F2E")
    static let teal = Color(hex: "4ECDC4")
    static let brightGreen = Color(hex: "2ECC71")
    static let windYellow = Color(hex: "F1C40F")
    static let windRed = Color(hex: "E74C3C")
    static let cardBackground = Color.white.opacity(0.06)
    static let cardBorder = Color(hex: "4ECDC4").opacity(0.25)
    static let subtleWhite = Color.white.opacity(0.7)
    static let dimWhite = Color.white.opacity(0.45)
    static let gold = Color(hex: "C8A84E")

    // MARK: - UIKit Colors (for CAShapeLayer / UILabel usage in RadarMapView)

    enum UIColors {
        /// Ruler dashed line — teal accent.
        static let rulerLine    = UIColor(red: 78/255, green: 205/255, blue: 196/255, alpha: 0.95)
        /// Ruler measurement label background — deepGulf with slight transparency.
        static let rulerLabelBg = UIColor(red: 10/255, green: 31/255, blue: 46/255, alpha: 0.85)
        /// Ruler measurement label font.
        static let rulerFont    = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    }
}

// MARK: - Glassmorphic Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var borderColor: Color = Theme.cardBorder
    var borderWidth: CGFloat = 0.7

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Theme.cardBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
            .shadow(color: Theme.teal.opacity(0.05), radius: 20)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - API Key (XOR-obfuscated — not in plain text in binary)

enum APIKeys {
    // XOR key used for obfuscation (not security — just avoids plain-text scanning)
    private static let xorKey: UInt8 = 0xAB

    // "e1f10a1e78da46f5b43e08d0f8b36e9b" XOR-encoded
    private static let encodedWeatherSTEM: [UInt8] = [
        0xCE, 0x9A, 0xCD, 0x9A, 0x9B, 0xCA, 0x9A, 0xCE,
        0x9C, 0x93, 0xCF, 0xCA, 0x9F, 0x9D, 0xCD, 0x9E,
        0xC9, 0x9F, 0x98, 0xCE, 0x9B, 0x93, 0xCF, 0x9B,
        0xCD, 0x93, 0xC9, 0x98, 0x9D, 0xCE, 0x92, 0xC9
    ]

    static var weatherSTEMKey: String {
        String(encodedWeatherSTEM.map { Character(UnicodeScalar($0 ^ xorKey)) })
    }

    // Mapbox public token XOR-encoded
    private static let encodedMapbox: [UInt8] = [
        0xDB, 0xC0, 0x85, 0xCE, 0xD2, 0xE1, 0x9A, 0xE2,
        0xC1, 0xC4, 0xC2, 0xCA, 0x98, 0xE9, 0xC2, 0xC8,
        0xC6, 0x92, 0xDE, 0xC8, 0x99, 0xDF, 0xDB, 0xE2,
        0xC2, 0xDC, 0xC2, 0xF2, 0xF8, 0xE2, 0x9D, 0xE2,
        0xC6, 0xE5, 0xDF, 0xC9, 0xFC, 0xE2, 0xD2, 0xE6,
        0xC5, 0xC7, 0xD8, 0xCE, 0xEF, 0xE9, 0xD8, 0xE5,
        0x98, 0xCC, 0xD2, 0xCF, 0xF3, 0xE9, 0x99, 0xC9,
        0xE3, 0xCF, 0x9F, 0xE6, 0x99, 0xED, 0xDB, 0xE4,
        0xEF, 0xC8, 0xC2, 0xCD, 0xFA, 0x85, 0xD3, 0xD8,
        0xC9, 0xFF, 0xD9, 0xE7, 0xE6, 0xCD, 0xD2, 0xEC,
        0x9D, 0xFB, 0xD3, 0xF4, 0xDD, 0xEC, 0xD2, 0xC2,
        0xD3, 0xEA, 0xC4, 0xDC
    ]

    static var mapboxAccessToken: String {
        String(encodedMapbox.map { Character(UnicodeScalar($0 ^ xorKey)) })
    }
}

// MARK: - Wind Color Helper

func windColor(for kts: Double) -> Color {
    if kts < 8 { return Theme.brightGreen }
    else if kts <= 12 { return Theme.windYellow }
    else { return Theme.windRed }
}
