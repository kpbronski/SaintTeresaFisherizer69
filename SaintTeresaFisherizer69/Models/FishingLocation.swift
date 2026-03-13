import Foundation

// MARK: - Fishing Location Configuration

/// Each fishing location encapsulates the full set of data-source
/// parameters needed by TideService, WeatherService, and WeatherSTEMService.
enum FishingLocation: String, CaseIterable, Identifiable, Sendable {
    case dogIslandReef
    case stMarks
    case stGeorgeIsland
    case aucillaMandalay
    case lanark
    case apalachicola
    case stVincentIndianPass
    case c23Buoy

    var id: String { rawValue }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .dogIslandReef:  "Dog Island Reef"
        case .stMarks:        "St. Marks"
        case .stGeorgeIsland: "St. George Island"
        case .aucillaMandalay: "Aucilla / Mandalay"
        case .lanark:          "Lanark"
        case .apalachicola:         "Apalachicola"
        case .stVincentIndianPass:  "St. Vincent / Indian Pass"
        case .c23Buoy:              "C23 Buoy (Offshore)"
        }
    }

    /// Short uppercase label used in the conditions panel header.
    var shortName: String {
        switch self {
        case .dogIslandReef:        "ON REEF"
        case .stMarks:              "AT ST. MARKS"
        case .stGeorgeIsland:       "AT SGI"
        case .aucillaMandalay:      "AT AUCILLA"
        case .lanark:               "AT LANARK"
        case .apalachicola:         "AT APALACH"
        case .stVincentIndianPass:  "AT INDIAN PASS"
        case .c23Buoy:              "AT C23 BUOY"
        }
    }

    /// Attribution line shown below the conditions panel header.
    var conditionsBlendLabel: String {
        switch self {
        case .dogIslandReef:        "DOG IS 60% · ALLIGATOR PT 20% · FSU CML 20%"
        case .stMarks:              "FSWN ST. MARKS LIGHTHOUSE"
        case .stGeorgeIsland:       "FSWN SGI LIGHTHOUSE"
        case .aucillaMandalay:      "FSWN ST. MARKS LIGHTHOUSE"
        case .lanark:               "FSWN ISLAND VIEW PARK"
        case .apalachicola:         "FSWN FRANKLIN COUNTY EOC"
        case .stVincentIndianPass:  "FSWN SALINAS PARK"
        case .c23Buoy:              "NDBC BUOY 42027 · 45M DEPTH"
        }
    }

    /// Subtitle for the 360-hour forecast card.
    var forecastSubtitle: String {
        switch self {
        case .dogIslandReef:        "360-Hour Forecast · Saint Teresa, FL"
        case .stMarks:              "360-Hour Forecast · St. Marks, FL"
        case .stGeorgeIsland:       "360-Hour Forecast · St. George Island, FL"
        case .aucillaMandalay:      "360-Hour Forecast · Aucilla River, FL"
        case .lanark:               "360-Hour Forecast · Lanark, FL"
        case .apalachicola:         "360-Hour Forecast · Apalachicola, FL"
        case .stVincentIndianPass:  "360-Hour Forecast · Indian Pass, FL"
        case .c23Buoy:              "360-Hour Forecast · C23 Buoy, Gulf of Mexico"
        }
    }

    /// SF Symbol shown in the location picker.
    var sfSymbol: String {
        switch self {
        case .dogIslandReef:        "water.waves"
        case .stMarks:              "lighthouse.fill"
        case .stGeorgeIsland:       "island.fill"
        case .aucillaMandalay:      "ferry.fill"
        case .lanark:               "binoculars.fill"
        case .apalachicola:         "building.2.fill"
        case .stVincentIndianPass:  "mappin.and.ellipse"
        case .c23Buoy:              "sensor.fill"
        }
    }

    /// NOAA station label for the chart footer.
    var stationLabel: String {
        let tc = tideConfig
        if tc.isSubordinate,
           let subID = tc.subordinateStationID,
           let subName = tc.subordinateStationName {
            return "NOAA \(subID) — \(subName) (via \(tc.referenceStationName))"
        }
        return "NOAA \(tc.referenceStationID) — \(tc.referenceStationName)"
    }

    // MARK: - Tide Configuration

    struct TideConfig: Sendable {
        let referenceStationID: String
        let referenceStationName: String
        let isSubordinate: Bool
        let subordinateStationID: String?
        let subordinateStationName: String?
        let highTimeOffsetMin: Int
        let lowTimeOffsetMin: Int
        let highHeightFactor: Double
        let lowHeightFactor: Double
    }

    var tideConfig: TideConfig {
        switch self {
        case .dogIslandReef:
            TideConfig(
                referenceStationID: "8728130",
                referenceStationName: "St. Marks Lighthouse",
                isSubordinate: true,
                subordinateStationID: "8728288",
                subordinateStationName: "St. Teresa",
                highTimeOffsetMin: -8,
                lowTimeOffsetMin: 11,
                highHeightFactor: 0.75,
                lowHeightFactor: 0.73
            )
        case .stMarks:
            TideConfig(
                referenceStationID: "8728130",
                referenceStationName: "St. Marks Lighthouse",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        case .stGeorgeIsland:
            TideConfig(
                referenceStationID: "8728669",
                referenceStationName: "Sikes Cut, St. George Island",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        case .aucillaMandalay:
            TideConfig(
                referenceStationID: "8728130",
                referenceStationName: "St. Marks Lighthouse",
                isSubordinate: true,
                subordinateStationID: "8727989",
                subordinateStationName: "Mandalay, Aucilla River",
                highTimeOffsetMin: 25,
                lowTimeOffsetMin: 57,
                highHeightFactor: 0.69,
                lowHeightFactor: 0.55
            )
        case .lanark:
            TideConfig(
                referenceStationID: "8728412",
                referenceStationName: "Lanark, St. Georges Sound",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        case .apalachicola:
            TideConfig(
                referenceStationID: "8728690",
                referenceStationName: "Apalachicola",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        case .stVincentIndianPass:
            TideConfig(
                referenceStationID: "8728852",
                referenceStationName: "Indian Pass",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        case .c23Buoy:
            TideConfig(
                referenceStationID: "8728690",
                referenceStationName: "Apalachicola",
                isSubordinate: false,
                subordinateStationID: nil,
                subordinateStationName: nil,
                highTimeOffsetMin: 0,
                lowTimeOffsetMin: 0,
                highHeightFactor: 1.0,
                lowHeightFactor: 1.0
            )
        }
    }

    // MARK: - Weather Configuration

    struct WeatherConfig: Sendable {
        let latitude: Double
        let longitude: Double
    }

    var weatherConfig: WeatherConfig {
        switch self {
        case .dogIslandReef:
            WeatherConfig(latitude: 29.787, longitude: -84.57)
        case .stMarks:
            WeatherConfig(latitude: 30.064, longitude: -84.178)
        case .stGeorgeIsland:
            WeatherConfig(latitude: 29.599, longitude: -84.958)
        case .aucillaMandalay:
            WeatherConfig(latitude: 30.127, longitude: -83.975)
        case .lanark:
            WeatherConfig(latitude: 29.864, longitude: -84.595)
        case .apalachicola:
            WeatherConfig(latitude: 29.710, longitude: -84.981)
        case .stVincentIndianPass:
            WeatherConfig(latitude: 29.685, longitude: -85.221)
        case .c23Buoy:
            WeatherConfig(latitude: 29.045, longitude: -85.305)
        }
    }

    // MARK: - WeatherSTEM Conditions Configuration

    struct ConditionsStationConfig: Sendable {
        let county: String
        let handle: String
        let weight: Double
    }

    struct ConditionsConfig: Sendable {
        let stations: [ConditionsStationConfig]
        let conditionsLatitude: Double
        let conditionsLongitude: Double
    }

    var conditionsConfig: ConditionsConfig {
        switch self {
        case .dogIslandReef:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "franklin", handle: "fswndogisland", weight: 0.60),
                    ConditionsStationConfig(county: "franklin", handle: "fswnalligatorpoint", weight: 0.20),
                    ConditionsStationConfig(county: "franklin", handle: "fsucml", weight: 0.20),
                ],
                conditionsLatitude: 29.81,
                conditionsLongitude: -84.59
            )
        case .stMarks:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "wakulla", handle: "fswnstmarks", weight: 1.0),
                ],
                conditionsLatitude: 30.074,
                conditionsLongitude: -84.180
            )
        case .stGeorgeIsland:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "franklin", handle: "fswnsgilighthouse", weight: 1.0),
                ],
                conditionsLatitude: 29.66,
                conditionsLongitude: -84.86
            )
        case .aucillaMandalay:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "wakulla", handle: "fswnstmarks", weight: 1.0),
                ],
                conditionsLatitude: 30.074,
                conditionsLongitude: -84.180
            )
        case .lanark:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "franklin", handle: "fswnislandviewpark", weight: 1.0),
                ],
                conditionsLatitude: 29.87,
                conditionsLongitude: -84.53
            )
        case .apalachicola:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "franklin", handle: "fswnfranklineoc", weight: 1.0),
                ],
                conditionsLatitude: 29.724,
                conditionsLongitude: -84.981
            )
        case .stVincentIndianPass:
            ConditionsConfig(
                stations: [
                    ConditionsStationConfig(county: "gulf", handle: "fswnsalinaspark", weight: 1.0),
                ],
                conditionsLatitude: 29.686,
                conditionsLongitude: -85.312
            )
        case .c23Buoy:
            ConditionsConfig(
                stations: [],
                conditionsLatitude: 29.045,
                conditionsLongitude: -85.305
            )
        }
    }

    // MARK: - NDBC Buoy Configuration

    struct NDBCConfig: Sendable {
        let buoyID: String
    }

    /// Returns the NDBC buoy config if this location uses buoy data for conditions.
    var ndbcConfig: NDBCConfig? {
        switch self {
        case .c23Buoy: NDBCConfig(buoyID: "42027")
        default: nil
        }
    }

    /// Whether this location uses NDBC buoy data instead of WeatherSTEM.
    var usesNDBC: Bool { ndbcConfig != nil }
}
