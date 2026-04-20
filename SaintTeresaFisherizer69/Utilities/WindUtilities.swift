import Foundation

// MARK: - Wind Direction & Weather Utilities

enum WindUtilities {

    /// Converts degrees (0–360) to 16-point compass direction.
    /// 0/360 = N, 90 = E, 180 = S, 270 = W
    static func cardinalDirection(from degrees: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let adjusted = (degrees + 11.25).truncatingRemainder(dividingBy: 360)
        let index = Int(adjusted / 22.5)
        return directions[max(0, min(index, 15))]
    }

    /// Converts wind-from degrees to an arrow showing the direction wind blows TOWARD.
    /// Wind FROM north (0°) blows south → "↓"
    /// Wind FROM east (90°) blows west → "←"
    static func arrowCharacter(from degrees: Double) -> String {
        let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
        let adjusted = (degrees + 22.5).truncatingRemainder(dividingBy: 360)
        let index = Int(adjusted / 45.0)
        return arrows[max(0, min(index, 7))]
    }

    /// Determines if a WMO weather code indicates rain or precipitation.
    static func isRainy(weatherCode: Int) -> Bool {
        (51...67).contains(weatherCode) ||
        (80...82).contains(weatherCode) ||
        (95...99).contains(weatherCode)
    }

    /// Converts Celsius to Fahrenheit.
    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9.0 / 5.0 + 32.0
    }

    /// SF Symbol for a WMO weather code (Open-Meteo hourly forecast).
    ///
    /// When `cloudCoverPercent` is available, interpolate the sky symbol across
    /// 5 tiers so a 30% cloudy sky looks distinctly different from a 60% cloudy sky:
    /// - 0–15%:  `sun.max.fill`   (bright clear)       / `moon.stars.fill`
    /// - 15–40%: `sun.min.fill`   (mainly clear)       / `moon.fill`
    /// - 40–60%: `sun.haze.fill`  (hazy, partly cloud) / `moon.haze.fill`
    /// - 60–75%: `cloud.sun.fill` (cloud covers sun)   / `cloud.moon.fill`
    /// - ≥ 75%:  `cloud.fill`     (fully overcast)
    /// Precipitation, fog, and thunderstorm codes always win since they carry
    /// more specific info than cloud cover alone.
    static func wmoSymbol(code: Int, isNight: Bool = false, cloudCoverPercent: Double? = nil) -> String {
        switch code {
        case 45, 48:        return "cloud.fog.fill"
        case 51, 53, 55:    return "cloud.drizzle.fill"
        case 56, 57:        return "cloud.sleet.fill"
        case 61, 63, 65:    return "cloud.rain.fill"
        case 66, 67:        return "cloud.sleet.fill"
        case 71, 73, 75:    return "cloud.snow.fill"
        case 77:            return "cloud.hail.fill"
        case 80, 81, 82:    return "cloud.heavyrain.fill"
        case 85, 86:        return "cloud.snow.fill"
        case 95:            return "cloud.bolt.rain.fill"
        case 96, 99:        return "cloud.bolt.fill"
        default: break
        }

        // Sky symbol interpolation by actual cloud cover %.
        if let pct = cloudCoverPercent {
            if pct < 15 {
                return isNight ? "moon.stars.fill" : "sun.max.fill"
            } else if pct < 40 {
                return isNight ? "moon.fill" : "sun.min.fill"
            } else if pct < 60 {
                return isNight ? "moon.haze.fill" : "sun.haze.fill"
            } else if pct < 75 {
                return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
            } else {
                return "cloud.fill"
            }
        }

        // Fallback: rely on the raw WMO code.
        switch code {
        case 0: return isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1: return isNight ? "moon.fill" : "sun.min.fill"
        case 2: return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        default: return "cloud.fill"
        }
    }

    /// Returns (primary, secondary) colors for palette-mode SF Symbol rendering.
    /// For SF Symbols like `cloud.sun.fill`, the **cloud** is the primary layer
    /// and the **sun** (modifier) is the secondary layer — so primary tints
    /// the cloud/base and secondary tints the accent (sun, bolt, rain, etc.).
    static func wmoSymbolColors(
        sym: String,
        baseRgb: (r: Int, g: Int, b: Int)
    ) -> (primary: (r: Int, g: Int, b: Int), secondary: (r: Int, g: Int, b: Int)) {
        let base = baseRgb
        let gold: (r: Int, g: Int, b: Int) = (255, 214, 51)
        let lightBlue: (r: Int, g: Int, b: Int) = (100, 181, 246)
        let white: (r: Int, g: Int, b: Int) = (236, 239, 241)

        // Single-layer glyphs, or dominant-accent glyphs (sun-first, moon-first).
        if sym == "sun.max.fill" || sym == "sun.min.fill" || sym == "sun.haze.fill" {
            return (gold, gold)      // whole-sun glyphs — all gold
        }
        if sym == "moon.fill" || sym == "moon.haze.fill" || sym == "cloud.fill" || sym == "cloud.fog.fill" {
            return (base, base)
        }

        // Two-layer: primary = cloud/base, secondary = accent.
        if sym.contains("sun") || sym.contains("bolt") {
            return (base, gold)          // cloud tint, yellow sun or bolt
        }
        if sym.contains("moon") {
            return (base, white)         // cloud tint, soft white moon
        }
        if sym.contains("rain") || sym.contains("drizzle") || sym.contains("sleet") {
            return (base, lightBlue)     // cloud tint, blue rain/drizzle
        }
        if sym.contains("snow") || sym.contains("hail") {
            return (base, white)         // cloud tint, white snow/hail
        }
        return (base, base)
    }

    /// Tint color for a WMO weather code, refined by cloud-cover% when available.
    static func wmoColor(code: Int, isNight: Bool = false, cloudCoverPercent: Double? = nil) -> (r: Int, g: Int, b: Int) {
        switch code {
        case 45, 48:            return (144, 164, 174)    // Fog — grey
        case 51...57:           return (100, 181, 246)    // Drizzle/freezing — blue
        case 61...67:           return (100, 181, 246)    // Rain — blue
        case 71...77, 85, 86:   return (179, 229, 252)    // Snow — light blue
        case 80...82:           return (100, 181, 246)    // Showers — blue
        case 95...99:           return (239, 83, 80)      // Thunderstorm — red
        default: break
        }

        // Clear/cloudy codes (0–3), refined by cloud cover across 5 tiers.
        if let pct = cloudCoverPercent {
            if pct < 15 {
                return isNight ? (210, 220, 235) : (255, 214, 51)  // Clear — gold/white
            } else if pct < 40 {
                return isNight ? (200, 210, 225) : (255, 224, 100) // Mainly clear — soft gold
            } else if pct < 60 {
                return isNight ? (190, 200, 215) : (220, 220, 210) // Hazy — muted gold-grey
            } else if pct < 75 {
                return isNight ? (180, 190, 210) : (200, 210, 220) // Partly cloudy
            } else {
                return (160, 170, 180)    // Overcast — grey
            }
        }

        switch code {
        case 0, 1: return isNight ? (210, 220, 235) : (255, 214, 51)
        case 2:    return isNight ? (180, 190, 210) : (200, 210, 220)
        case 3:    return (160, 170, 180)
        default:   return (200, 200, 210)
        }
    }

    /// SF Symbol for a TWC (The Weather Company) icon code used by WeatherSTEM.
    static func conditionSymbol(iconCode: Int) -> String {
        switch iconCode {
        case 0...5, 37, 38, 47:     "cloud.bolt.rain.fill"
        case 6, 8, 10:              "cloud.sleet.fill"
        case 11, 12, 39, 40, 45:    "cloud.rain.fill"
        case 9:                      "cloud.drizzle.fill"
        case 13...16, 41...43, 46:  "cloud.snow.fill"
        case 17, 35:                "cloud.hail.fill"
        case 18:                    "cloud.sleet.fill"
        case 19:                    "sun.dust.fill"
        case 20, 21, 22:           "cloud.fog.fill"
        case 23, 24:               "wind"
        case 25:                    "thermometer.snowflake"
        case 26:                    "cloud.fill"
        case 27, 28:               "cloud.fill"
        case 29, 30:               "cloud.sun.fill"
        case 31, 33:               "moon.stars.fill"
        case 32, 34:               "sun.max.fill"
        case 36:                    "sun.max.fill"
        default:                    "cloud.fill"
        }
    }

    /// Accent color for a TWC icon code.
    static func conditionColor(iconCode: Int) -> (r: Int, g: Int, b: Int) {
        switch iconCode {
        case 0...5, 37, 38, 47:     (239, 83, 80)    // Thunderstorm — red
        case 6...12, 17, 18, 35,
             39, 40, 45:            (100, 181, 246)   // Rain/sleet — blue
        case 13...16, 41...43, 46:  (179, 229, 252)   // Snow — light blue
        case 19...22:               (144, 164, 174)   // Fog/haze — grey
        case 23, 24, 25:           (144, 164, 174)   // Wind/frigid — grey
        case 26...28:              (160, 170, 180)   // Cloudy — grey
        case 29, 30:               (200, 210, 220)   // Partly cloudy — light
        case 31, 33:               (180, 190, 220)   // Clear night — soft blue
        case 32, 34, 36:           (255, 214, 51)    // Sunny/fair — gold
        default:                    (200, 200, 210)
        }
    }
}
