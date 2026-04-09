import SwiftUI
import UIKit
@preconcurrency @_spi(Experimental) import MapboxMaps

// MARK: - Particle Config

enum WindParticleConfig {
    static let count: Int = 4_000
    static let lifespanFrames: Int = 80          // ~1.3s at 60fps
    static let baseSpeedScalar: Float = 0.0006   // tunes visual speed independent of wind
    static let tailLength: Int = 6               // number of trail segments per particle
    static let headAlpha: CGFloat = 0.7
    static let lineWidth: CGFloat = 1.0
}

// MARK: - Particle

private struct Particle {
    /// Normalized position within bbox [0, 1]
    var x: Float
    var y: Float
    var age: Int
    var seed: Float
    /// Recent position history for trail rendering (newest first)
    var trail: [(Float, Float)]

    static func random(seed: Float) -> Particle {
        let x = Float.random(in: 0...1)
        let y = Float.random(in: 0...1)
        return Particle(
            x: x, y: y,
            age: Int.random(in: 0..<WindParticleConfig.lifespanFrames),
            seed: seed,
            trail: Array(repeating: (x, y), count: WindParticleConfig.tailLength)
        )
    }
}

// MARK: - SwiftUI Representable

/// SwiftUI wrapper that overlays animated wind particles.
/// Must be placed on top of the RadarMapView in the same ZStack.
struct WindParticleView: UIViewRepresentable {
    let snapshot: WindFieldSnapshot?
    let mapViewProvider: () -> MapView?

    func makeUIView(context: Context) -> WindParticleCanvas {
        let canvas = WindParticleCanvas(frame: .zero)
        canvas.mapViewProvider = mapViewProvider
        return canvas
    }

    func updateUIView(_ canvas: WindParticleCanvas, context: Context) {
        canvas.mapViewProvider = mapViewProvider
        if let snapshot {
            canvas.snapshot = snapshot
            if !canvas.isAnimating {
                canvas.startAnimating()
            }
        } else {
            canvas.stopAnimating()
        }
    }

    static func dismantleUIView(_ canvas: WindParticleCanvas, coordinator: ()) {
        canvas.stopAnimating()
    }
}

// MARK: - Wind Particle Canvas

/// Renders animated wind particles as short line-segment trails.
/// No accumulation buffer — each frame is drawn fresh from particle
/// position histories, so it works correctly at all zoom levels
/// and during map pan/zoom.
final class WindParticleCanvas: UIView {

    // MARK: - State

    private var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private(set) var isAnimating = false
    // Clipping handled by CG quad path in tick()

    var snapshot: WindFieldSnapshot? {
        didSet { updateWindTexture() }
    }

    var mapViewProvider: (() -> MapView?)?

    // MARK: - Wind Data

    private var uGrid: [Float] = []
    private var vGrid: [Float] = []
    private var gridW: Int = 0
    private var gridH: Int = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        initParticles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Lifecycle

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30, maximum: 120, preferred: 60
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopAnimating() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        layer.contents = nil
    }

    // MARK: - Particle Init

    private func initParticles() {
        particles = (0..<WindParticleConfig.count).map { i in
            Particle.random(seed: Float(i) / Float(WindParticleConfig.count))
        }
    }

    private func updateWindTexture() {
        guard let snap = snapshot else { return }
        uGrid = snap.u
        vGrid = snap.v
        gridW = snap.gridWidth
        gridH = snap.gridHeight
    }

    // MARK: - Per-Frame Update

    // MARK: - Web Mercator Projection

    /// Projects a geographic coordinate to screen points using the camera state.
    /// Unlike MapboxMap.point(for:), this does NOT clamp off-screen points to (-1,-1),
    /// which is critical for building a correct clip quad when corners are off-screen
    /// (e.g., at low zoom with map rotation).
    private func projectCorners(
        bbox: GeographicBoundingBox,
        map: MapboxMap,
        viewSize: CGSize
    ) -> (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint)? {
        let camera = map.cameraState

        // Web Mercator: lat/lon → normalized [0,1] space
        func mercX(_ lon: Double) -> Double { (lon + 180.0) / 360.0 }
        func mercY(_ lat: Double) -> Double {
            let r = lat * .pi / 180.0
            return (1.0 - log(tan(r) + 1.0 / cos(r)) / .pi) / 2.0
        }

        // Camera center in Mercator
        let cx = mercX(camera.center.longitude)
        let cy = mercY(camera.center.latitude)

        // Calibrate world scale by projecting camera center + a nearby point.
        // Both are guaranteed on-screen at any bearing.
        let centerScreen = map.point(for: camera.center)
        guard centerScreen.x > -0.5 else { return nil }  // center should never clamp

        let offset = 0.001  // ~100m — always on screen
        let nearCoord = CLLocationCoordinate2D(
            latitude: camera.center.latitude,
            longitude: camera.center.longitude + offset
        )
        let nearScreen = map.point(for: nearCoord)
        guard nearScreen.x > -0.5 else { return nil }

        let dMerc = abs(mercX(nearCoord.longitude) - cx)
        let dsx = Double(nearScreen.x - centerScreen.x)
        let dsy = Double(nearScreen.y - centerScreen.y)
        let dScreen = sqrt(dsx * dsx + dsy * dsy)
        guard dMerc > 1e-12, dScreen > 0.01 else { return nil }
        let worldSize = dScreen / dMerc

        // Bearing rotation
        let bearingRad = -camera.bearing * .pi / 180.0
        let cosB = cos(bearingRad)
        let sinB = sin(bearingRad)

        func project(lat: Double, lon: Double) -> CGPoint {
            let dx = (mercX(lon) - cx) * worldSize
            let dy = (mercY(lat) - cy) * worldSize
            let rx = dx * cosB - dy * sinB
            let ry = dx * sinB + dy * cosB
            return CGPoint(
                x: Double(centerScreen.x) + rx,
                y: Double(centerScreen.y) + ry
            )
        }

        return (
            tl: project(lat: bbox.maxLat, lon: bbox.minLon),
            tr: project(lat: bbox.maxLat, lon: bbox.maxLon),
            bl: project(lat: bbox.minLat, lon: bbox.minLon),
            br: project(lat: bbox.minLat, lon: bbox.maxLon)
        )
    }

    @objc private func tick() {
        guard let snapshot,
              let mapView = mapViewProvider?(),
              let map = mapView.mapboxMap else { return }
        let bbox = snapshot.bbox

        // Project bbox corners using our own Mercator math (avoids Mapbox's off-screen clamping)
        guard let corners = projectCorners(bbox: bbox, map: map, viewSize: mapView.bounds.size) else { return }
        let tl = corners.tl, tr = corners.tr, bl = corners.bl, br = corners.br

        // Build quadrilateral path for the projected bbox (handles map rotation)
        let quadPath = UIBezierPath()
        quadPath.move(to: tl)
        quadPath.addLine(to: tr)
        quadPath.addLine(to: br)
        quadPath.addLine(to: bl)
        quadPath.close()

        let quadBounds = quadPath.bounds
        guard quadBounds.width > 1, quadBounds.height > 1 else { return }

        // Bilinear mapping closures: normalized [0,1] grid coords → screen coords
        // through the 4 projected corners. Handles rotation/tilt correctly.
        let _tl = tl, _tr = tr, _bl = bl, _br = br
        let mapX = { (nx: CGFloat, ny: CGFloat) -> CGFloat in
            let bx = _bl.x + (_br.x - _bl.x) * nx
            let tx = _tl.x + (_tr.x - _tl.x) * nx
            return bx + (tx - bx) * ny
        }
        let mapY = { (nx: CGFloat, ny: CGFloat) -> CGFloat in
            let by = _bl.y + (_br.y - _bl.y) * nx
            let ty = _tl.y + (_tr.y - _tl.y) * nx
            return by + (ty - by) * ny
        }

        // Scale particle render count by zoom — fewer at low zoom where the quad is small
        let zoom = map.cameraState.zoom
        let renderCount: Int
        if zoom < 8 {
            renderCount = min(particles.count, 800)
        } else if zoom < 9 {
            renderCount = min(particles.count, 1500)
        } else if zoom < 10.5 {
            renderCount = min(particles.count, 2500)
        } else {
            renderCount = particles.count
        }

        // Update particles
        let speed = WindParticleConfig.baseSpeedScalar
        let lifespan = WindParticleConfig.lifespanFrames
        let tailLen = WindParticleConfig.tailLength

        for i in 0..<particles.count {
            var p = particles[i]

            let (u, v) = sampleUV(nx: p.x, ny: p.y)

            let lonSpan = Float(bbox.maxLon - bbox.minLon)
            let latSpan = Float(bbox.maxLat - bbox.minLat)

            let dx = (u / 96_000.0) / lonSpan / 60.0 * speed * 1_000_000
            let dy = (v / 111_000.0) / latSpan / 60.0 * speed * 1_000_000

            // Push current position into trail history
            p.trail.insert((p.x, p.y), at: 0)
            if p.trail.count > tailLen {
                p.trail.removeLast(p.trail.count - tailLen)
            }

            p.x += dx
            p.y += dy
            p.age += 1

            // Respawn if expired or out of bounds
            if p.age >= lifespan || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1 {
                p.x = Float.random(in: 0...1)
                p.y = Float.random(in: 0...1)
                p.age = 0
                p.trail = Array(repeating: (p.x, p.y), count: tailLen)
            }

            particles[i] = p
        }

        // Render — fresh each frame, no accumulation buffer.
        guard bounds.width > 0, bounds.height > 0 else { return }

        let visibleClip = quadBounds.intersection(CGRect(origin: .zero, size: bounds.size))
        guard !visibleClip.isEmpty else {
            layer.contents = nil
            return
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1x for perf — 3x is 9x more pixels, kills frame rate
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        let image = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext

            ctx.saveGState()

            // === DIAGNOSTIC (Phase 1) — red quad stroke before clip ===
            if Self.debugDrawHeatmapQuad {
                ctx.setStrokeColor(UIColor.red.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(4.0)
                ctx.addPath(quadPath.cgPath)
                ctx.strokePath()
            }

            // Clip to the projected heatmap quad
            ctx.addPath(quadPath.cgPath)
            ctx.clip()

            // Draw particle trails
            let headAlpha = WindParticleConfig.headAlpha
            let bandAlphas: [CGFloat] = [headAlpha, headAlpha * 0.6, headAlpha * 0.25]
            let bandWidths: [CGFloat] = [1.0, 0.8, 0.6]
            let segmentsPerBand = max(1, tailLen / 3)

            for band in 0..<3 {
                let path = CGMutablePath()
                let startSeg = band * segmentsPerBand
                let endSeg = min(startSeg + segmentsPerBand, tailLen)

                for i in 0..<renderCount {
                    let p = particles[i]
                    let pnx = CGFloat(p.x), pny = CGFloat(p.y)
                    let hx = mapX(pnx, pny)
                    let hy = mapY(pnx, pny)

                    guard hx >= visibleClip.minX - 30 && hx <= visibleClip.maxX + 30 &&
                          hy >= visibleClip.minY - 30 && hy <= visibleClip.maxY + 30 else { continue }

                    let lifeFrac = Float(p.age) / Float(lifespan)
                    if lifeFrac < 0.05 || lifeFrac > 0.97 { continue }

                    let allPoints: [CGPoint] = {
                        var pts = [CGPoint(x: hx, y: hy)]
                        for pos in p.trail {
                            let tnx = CGFloat(pos.0), tny = CGFloat(pos.1)
                            pts.append(CGPoint(x: mapX(tnx, tny), y: mapY(tnx, tny)))
                        }
                        return pts
                    }()

                    guard startSeg < allPoints.count - 1 else { continue }
                    let fromIdx = startSeg
                    let toIdx = min(endSeg, allPoints.count - 1)

                    path.move(to: allPoints[fromIdx])
                    for s in (fromIdx + 1)...toIdx {
                        path.addLine(to: allPoints[s])
                    }
                }

                ctx.setStrokeColor(UIColor.white.withAlphaComponent(bandAlphas[band]).cgColor)
                ctx.setLineWidth(bandWidths[band])
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(path)
                ctx.strokePath()
            }

            ctx.restoreGState()
        }

        layer.contentsScale = format.scale
        layer.contentsGravity = .resize
        layer.contents = image.cgImage
    }

    #if DEBUG
    static var debugDrawHeatmapQuad: Bool = false  // flip to true to see red clip quad
    #else
    static var debugDrawHeatmapQuad: Bool = false
    #endif

    // MARK: - Bilinear U/V Sampling

    private func sampleUV(nx: Float, ny: Float) -> (Float, Float) {
        guard gridW > 0, gridH > 0,
              uGrid.count >= gridW * gridH,
              vGrid.count >= gridW * gridH else {
            return (0, 0)
        }

        let gx = nx * Float(gridW - 1)
        let gy = ny * Float(gridH - 1)

        let x0 = max(0, min(Int(gx), gridW - 1))
        let y0 = max(0, min(Int(gy), gridH - 1))
        let x1 = min(x0 + 1, gridW - 1)
        let y1 = min(y0 + 1, gridH - 1)

        let fx = gx - Float(x0)
        let fy = gy - Float(y0)

        let idx00 = y0 * gridW + x0
        let idx10 = y0 * gridW + x1
        let idx01 = y1 * gridW + x0
        let idx11 = y1 * gridW + x1

        let u = uGrid[idx00] * (1 - fx) * (1 - fy)
              + uGrid[idx10] * fx * (1 - fy)
              + uGrid[idx01] * (1 - fx) * fy
              + uGrid[idx11] * fx * fy

        let v = vGrid[idx00] * (1 - fx) * (1 - fy)
              + vGrid[idx10] * fx * (1 - fy)
              + vGrid[idx01] * (1 - fx) * fy
              + vGrid[idx11] * fx * fy

        return (u, v)
    }
}
