// DrawingState.swift — Saint Teresa Fisherizer 69
//
// Data model for freehand drawing annotations. Strokes are stored as
// geographic coordinates (lat/lon) so they stay anchored to the map.
// Manages undo/redo action stack, color/size, and UserDefaults persistence.

import SwiftUI
import CoreLocation

// MARK: - Stroke

struct Stroke: Identifiable, Codable {
    let id: UUID
    var coordinates: [CodableCoordinate]
    var colorHex: String
    var lineWidth: CGFloat

    init(id: UUID = UUID(), coordinates: [CLLocationCoordinate2D] = [], color: UIColor, lineWidth: CGFloat) {
        self.id = id
        self.coordinates = coordinates.map { CodableCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        self.colorHex = color.hexString
        self.lineWidth = lineWidth
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var uiColor: UIColor {
        UIColor(hex: colorHex) ?? .orange
    }
}

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Drawing Action (Undo/Redo)

enum DrawingAction {
    case add(Stroke)
    case erase(Stroke)
    case clearAll([Stroke])
}

// MARK: - Preset Colors

enum DrawingColor: CaseIterable {
    case red, orange, yellow, green, blue, white

    var uiColor: UIColor {
        switch self {
        case .red:    return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        case .yellow: return UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        case .green:  return UIColor(red: 0.30, green: 0.85, blue: 0.39, alpha: 1)
        case .blue:   return UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        case .white:  return UIColor.white
        }
    }

    var color: Color { Color(uiColor) }

    var label: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .white: "White"
        }
    }
}

// MARK: - Brush Size

enum BrushSize: CGFloat, CaseIterable {
    case thin = 3
    case medium = 5
    case thick = 8

    var label: String {
        "\(Int(rawValue))pt"
    }

    var next: BrushSize {
        switch self {
        case .thin: .medium
        case .medium: .thick
        case .thick: .thin
        }
    }
}

// MARK: - Drawing State

@Observable
final class DrawingState {

    var strokes: [Stroke] = []
    var selectedColor: DrawingColor = .red
    var selectedSize: BrushSize = .medium
    var isErasing: Bool = false

    /// Monotonically increasing counter — bumped on every stroke mutation.
    private(set) var strokeVersion: Int = 0

    private var undoStack: [DrawingAction] = []
    private var redoStack: [DrawingAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Actions

    func commitStroke(_ stroke: Stroke) {
        guard stroke.coordinates.count >= 2 else { return }
        strokes.append(stroke)
        undoStack.append(.add(stroke))
        redoStack.removeAll()
        strokeVersion += 1
    }

    func eraseStroke(withID id: UUID) {
        guard let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        let removed = strokes.remove(at: idx)
        undoStack.append(.erase(removed))
        redoStack.removeAll()
        strokeVersion += 1
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .add(let stroke):
            strokes.removeAll { $0.id == stroke.id }
            redoStack.append(.add(stroke))
        case .erase(let stroke):
            strokes.append(stroke)
            redoStack.append(.erase(stroke))
        case .clearAll(let cleared):
            strokes.append(contentsOf: cleared)
            redoStack.append(.clearAll(cleared))
        }
        strokeVersion += 1
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        switch action {
        case .add(let stroke):
            strokes.append(stroke)
            undoStack.append(.add(stroke))
        case .erase(let stroke):
            strokes.removeAll { $0.id == stroke.id }
            undoStack.append(.erase(stroke))
        case .clearAll(let cleared):
            strokes.removeAll()
            undoStack.append(.clearAll(cleared))
        }
        strokeVersion += 1
    }

    func clearAll() {
        guard !strokes.isEmpty else { return }
        let cleared = strokes
        strokes.removeAll()
        undoStack.append(.clearAll(cleared))
        redoStack.removeAll()
        strokeVersion += 1
    }

    // MARK: - Persistence

    private static let storageKey = "Fisherizer_DrawingStrokes"

    func save() {
        guard let data = try? JSONEncoder().encode(strokes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Stroke].self, from: data) else { return }
        strokes = saved
        undoStack.removeAll()
        redoStack.removeAll()
        strokeVersion += 1
    }
}

// MARK: - UIColor Hex Helpers

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}
