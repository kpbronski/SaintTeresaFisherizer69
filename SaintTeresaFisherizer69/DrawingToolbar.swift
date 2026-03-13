// DrawingToolbar.swift — Saint Teresa Fisherizer 69
//
// ForeFlight-style drawing toolbar. Appears below the top bar
// when drawing mode is active.
//
// Layout: Color swatch · Brush size · Eraser ·· Clear · Undo · Redo · Done

import SwiftUI

struct DrawingToolbar: View {

    @Bindable var drawingState: DrawingState
    var onDone: () -> Void

    @State private var showColorPicker = false

    private let accentText = Color.white.opacity(0.85)

    var body: some View {
        HStack(spacing: 6) {

            // ── Color Swatch ──
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showColorPicker.toggle()
                }
            } label: {
                Circle()
                    .fill(drawingState.selectedColor.color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                drawingState.isErasing ? Color.white.opacity(0.3) : Theme.teal,
                                lineWidth: 2
                            )
                    )
            }
            .accessibilityLabel("Stroke color: \(drawingState.selectedColor.label)")

            // ── Brush Size ──
            Button {
                drawingState.selectedSize = drawingState.selectedSize.next
                drawingState.isErasing = false
            } label: {
                Text(drawingState.selectedSize.label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(drawingState.isErasing ? accentText.opacity(0.5) : accentText)
                    .frame(width: 40, height: 36)
            }
            .accessibilityLabel("Brush size: \(drawingState.selectedSize.label)")

            // ── Eraser ──
            Button {
                drawingState.isErasing.toggle()
            } label: {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(drawingState.isErasing ? Theme.teal : accentText.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        drawingState.isErasing
                            ? Theme.teal.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .accessibilityLabel(drawingState.isErasing ? "Eraser active" : "Eraser")

            Spacer()

            // ── Clear ──
            Button {
                drawingState.clearAll()
            } label: {
                Text("Clear")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(drawingState.strokes.isEmpty ? accentText.opacity(0.3) : accentText)
            }
            .disabled(drawingState.strokes.isEmpty)

            // ── Undo ──
            Button {
                drawingState.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(drawingState.canUndo ? accentText : accentText.opacity(0.3))
                    .frame(width: 36, height: 36)
            }
            .disabled(!drawingState.canUndo)

            // ── Redo ──
            Button {
                drawingState.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(drawingState.canRedo ? accentText : accentText.opacity(0.3))
                    .frame(width: 36, height: 36)
            }
            .disabled(!drawingState.canRedo)

            // ── Done ──
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.teal)
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(toolbarBackground)
        .overlay(alignment: .bottomLeading) {
            if showColorPicker {
                colorPickerPopover
                    .offset(x: 4, y: 52)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
            }
        }
    }

    // MARK: - Color Picker Popover

    private var colorPickerPopover: some View {
        HStack(spacing: 8) {
            ForEach(DrawingColor.allCases, id: \.label) { color in
                Button {
                    drawingState.selectedColor = color
                    drawingState.isErasing = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        showColorPicker = false
                    }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    drawingState.selectedColor.label == color.label
                                        ? Theme.teal
                                        : Color.white.opacity(0.2),
                                    lineWidth: drawingState.selectedColor.label == color.label ? 2.5 : 1
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.deepGulf.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Toolbar Background

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.deepGulf.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}
