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
    static func wmoSymbol(code: Int) -> String {
        switch code {
        case 0:             "sun.max.fill"
        case 1:             "sun.min.fill"
        case 2:             "cloud.sun.fill"
        case 3:             "cloud.fill"
        case 45, 48:        "cloud.fog.fill"
        case 51, 53, 55:    "cloud.drizzle.fill"
        case 56, 57:        "cloud.sleet.fill"
        case 61, 63, 65:    "cloud.rain.fill"
        case 66, 67:        "cloud.sleet.fill"
        case 71, 73, 75:    "cloud.snow.fill"
        case 77:            "cloud.hail.fill"
        case 80, 81, 82:    "cloud.heavyrain.fill"
        case 85, 86:        "cloud.snow.fill"
        case 95:            "cloud.bolt.rain.fill"
        case 96, 99:        "cloud.bolt.fill"
        default:            "cloud.fill"
        }
    }

    /// Tint color for a WMO weather code.
    static func wmoColor(code: Int) -> (r: Int, g: Int, b: Int) {
        switch code {
        case 0, 1:              (255, 214, 51)    // Clear/sunny — gold
        case 2:                 (200, 210, 220)    // Partly cloudy — light
        case 3:                 (160, 170, 180)    // Overcast — grey
        case 45, 48:            (144, 164, 174)    // Fog — grey
        case 51...57:           (100, 181, 246)    // Drizzle/freezing — blue
        case 61...67:           (100, 181, 246)    // Rain — blue
        case 71...77, 85, 86:   (179, 229, 252)    // Snow — light blue
        case 80...82:           (100, 181, 246)    // Showers — blue
        case 95...99:           (239, 83, 80)      // Thunderstorm — red
        default:                (200, 200, 210)
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
