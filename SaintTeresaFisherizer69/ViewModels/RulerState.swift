// RulerState.swift — Saint Teresa Fisherizer 69
//
// Observable state for the map ruler/measurement tool.
// Stores geographic endpoints, computes great-circle distance and magnetic
// bearing. Rendering is handled by RadarMapView Coordinator via CAShapeLayer.

import Foundation
import CoreLocation

@Observable
final class RulerState {

    // MARK: - State

    var isVisible: Bool = false
    var startCoordinate: CLLocationCoordinate2D?
    var endCoordinate: CLLocationCoordinate2D?

    /// Monotonically increasing counter — bumped on every change.
    private(set) var version: Int = 0

    /// Magnetic declination in degrees (positive = east, negative = west).
    /// Big Bend FL coast ≈ -5°
    var magneticDeclination: Double = -5.0

    // MARK: - Computed Measurements

    var hasEndpoints: Bool {
        startCoordinate != nil && endCoordinate != nil
    }

    /// Great-circle distance in nautical miles.
    var distanceNM: Double? {
        guard let s = startCoordinate, let e = endCoordinate else { return nil }
        return Self.haversineNM(from: s, to: e)
    }

    /// Distance in feet.
    var distanceFeet: Double? {
        guard let nm = distanceNM else { return nil }
        return nm * 6076.12
    }

    /// Initial magnetic bearing from start → end.
    var forwardBearingMagnetic: Double? {
        guard let s = startCoordinate, let e = endCoordinate else { return nil }
        let trueBearing = Self.initialBearing(from: s, to: e)
        return Self.normalizeBearing(trueBearing - magneticDeclination)
    }

    /// Initial magnetic bearing from end → start.
    var reverseBearingMagnetic: Double? {
        guard let s = startCoordinate, let e = endCoordinate else { return nil }
        let trueBearing = Self.initialBearing(from: e, to: s)
        return Self.normalizeBearing(trueBearing - magneticDeclination)
    }

    // MARK: - Display Formatters

    var displayDistance: String {
        guard let nm = distanceNM, let ft = distanceFeet else { return "" }
        if nm >= 3.0 {
            return String(format: "%.1f NM", nm)
        } else if nm >= 0.1 {
            let feetStr = Self.numberFormatter.string(from: NSNumber(value: Int(ft))) ?? "\(Int(ft))"
            return String(format: "%.1f NM · %@ ft", nm, feetStr)
        } else {
            let feetStr = Self.numberFormatter.string(from: NSNumber(value: Int(ft))) ?? "\(Int(ft))"
            return "\(feetStr) ft"
        }
    }

    var forwardBearingDisplay: String {
        guard let b = forwardBearingMagnetic else { return "" }
        return String(format: "%03.0f°M", b)
    }

    var reverseBearingDisplay: String {
        guard let b = reverseBearingMagnetic else { return "" }
        return String(format: "%03.0f°M", b)
    }

    // MARK: - Mutations

    func update(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        startCoordinate = start
        endCoordinate = end
        isVisible = true
        version += 1
    }

    func updateStart(_ coord: CLLocationCoordinate2D) {
        startCoordinate = coord
        version += 1
    }

    func updateEnd(_ coord: CLLocationCoordinate2D) {
        endCoordinate = coord
        version += 1
    }

    func clear() {
        startCoordinate = nil
        endCoordinate = nil
        isVisible = false
        version += 1
    }

    // MARK: - Haversine Distance (Nautical Miles)

    static func haversineNM(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 3440.065 // Earth radius in nautical miles
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180

        let sinHalfDLat = sin(dLat / 2)
        let sinHalfDLon = sin(dLon / 2)
        let h = sinHalfDLat * sinHalfDLat + cos(lat1) * cos(lat2) * sinHalfDLon * sinHalfDLon
        return 2 * R * asin(sqrt(h))
    }

    // MARK: - Initial Bearing (True, Degrees)

    static func initialBearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let x = sin(dLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(x, y) * 180 / .pi
        return normalizeBearing(bearing)
    }

    // MARK: - Helpers

    static func normalizeBearing(_ bearing: Double) -> Double {
        var b = bearing.truncatingRemainder(dividingBy: 360)
        if b < 0 { b += 360 }
        return b
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()
}
