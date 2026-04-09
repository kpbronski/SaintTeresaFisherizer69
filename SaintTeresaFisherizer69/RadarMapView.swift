// RadarMapView.swift — Saint Teresa Fisherizer 69
//
// UIViewRepresentable Mapbox Maps SDK v11 wrapper with ruler measurement
// tool and freehand drawing annotations. Radar/weather layers to be added later.

import SwiftUI
@preconcurrency @_spi(Experimental) import MapboxMaps

// MARK: - Constants

private enum MapConstants {
    static let style = StyleURI.dark

    static let initialCamera = CameraOptions(
        center:  CLLocationCoordinate2D(latitude: 29.8, longitude: -84.6),
        zoom:    8,
        bearing: 0,
        pitch:   0
    )
}

// MARK: - Shared MapView Reference

/// Allows SwiftUI siblings to access the MapView for coordinate projection.
final class MapViewReference: @unchecked Sendable {
    weak var mapView: MapView?
}

// MARK: - UIViewRepresentable

struct RadarMapView: UIViewRepresentable {

    var mapViewRef: MapViewReference?
    var rulerState: RulerState
    var drawingState: DrawingState
    var isDrawing: Bool
    var useAerialMap: Bool
    var showNEXRAD: Bool
    var nexradFrameIndex: Int    // 0 = oldest (-120 min), 23 = live
    var showHRRR: Bool
    var hrrrFrameIndex: Int      // 0 = F0000 (now), 72 = F1080 (+18h)
    var showENC: Bool
    var showGOESIR: Bool
    var showGOESVis: Bool
    var showWindHeatmap: Bool
    var windSnapshot: WindFieldSnapshot?
    var resetNorthTrigger: Int
    var chartTileCache: ChartTileCacheService
    var onStyleLoaded: (() -> Void)?

    // MARK: Make

    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions(styleURI: MapConstants.style)
        let mapView = MapView(frame: .zero, mapInitOptions: options)

        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Clean look — hide all ornaments
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.logo.margins              = CGPoint(x: -200, y: -200)
        mapView.ornaments.options.attributionButton.margins  = CGPoint(x: -200, y: -200)

        mapView.mapboxMap.setCamera(to: MapConstants.initialCamera)

        // Expose MapView to SwiftUI siblings for particle overlay
        mapViewRef?.mapView = mapView

        let coord = context.coordinator
        coord.mapViewRef = mapView

        // Style loaded observer
        coord.styleLoadedCancelable = mapView.mapboxMap.onStyleLoaded.observeNext { [weak mapView, weak coord] _ in
            guard let mapView, let coord else { return }
            coord.styleDidLoad(mapView: mapView)
        }

        // Camera change observer — keeps ruler rendering in sync with map movement
        coord.cameraChangeCancelable = mapView.mapboxMap.onCameraChanged.observeNext { [weak coord] _ in
            coord?.updateRulerRendering()
        }

        // Ruler: 2-finger long press
        let longPress = UILongPressGestureRecognizer(target: coord, action: #selector(Coordinator.handleRulerLongPress(_:)))
        longPress.numberOfTouchesRequired = 2
        longPress.minimumPressDuration = 0.3
        mapView.addGestureRecognizer(longPress)
        coord.rulerLongPress = longPress

        return mapView
    }

    // MARK: Update

    func updateUIView(_ mapView: MapView, context: Context) {
        let coord = context.coordinator

        // ── Reset North ──
        if resetNorthTrigger != coord.lastResetNorthTrigger {
            coord.lastResetNorthTrigger = resetNorthTrigger
            mapView.camera.ease(
                to: CameraOptions(bearing: 0, pitch: 0),
                duration: 0.4,
                curve: .easeInOut,
                completion: nil
            )
        }

        // ── Base map style toggle ──
        let targetStyle: StyleURI = useAerialMap ? .satelliteStreets : .dark
        if targetStyle != coord.currentStyleURI {
            coord.currentStyleURI = targetStyle
            mapView.mapboxMap.loadStyle(targetStyle)
        }

        // ── NEXRAD toggle ──
        if showNEXRAD != coord.showNEXRAD {
            coord.showNEXRAD = showNEXRAD
            if showNEXRAD {
                if coord.nexradSourceAdded {
                    coord.setNEXRADVisibility(true, on: mapView)
                } else {
                    coord.preloadNEXRADLayers(on: mapView, initialFrame: nexradFrameIndex)
                }
            } else {
                coord.setNEXRADVisibility(false, on: mapView)
            }
        }

        // ── NEXRAD frame change ──
        if showNEXRAD && nexradFrameIndex != coord.activeNEXRADFrame {
            coord.showNEXRADFrame(nexradFrameIndex)
        }

        // ── HRRR REFD toggle ──
        if showHRRR != coord.showHRRR {
            coord.showHRRR = showHRRR
            if showHRRR {
                if coord.hrrrSourceAdded {
                    coord.setHRRRVisibility(true, on: mapView)
                } else {
                    coord.preloadHRRRLayers(on: mapView, initialFrame: hrrrFrameIndex)
                }
            } else {
                coord.setHRRRVisibility(false, on: mapView)
            }
        }

        // ── HRRR frame change ──
        if showHRRR && hrrrFrameIndex != coord.activeHRRRFrame {
            coord.showHRRRFrame(hrrrFrameIndex)
        }

        // ── NOAA ENC Chart toggle ──
        if showENC != coord.showENC {
            coord.showENC = showENC
            if showENC {
                if !coord.encSourceAdded {
                    coord.addENCLayer(on: mapView)
                } else {
                    coord.setENCVisibility(true, on: mapView)
                }
            } else {
                coord.setENCVisibility(false, on: mapView)
            }
        }

        // ── GOES IR toggle ──
        if showGOESIR != coord.showGOESIR {
            coord.showGOESIR = showGOESIR
            if showGOESIR {
                if !coord.goesIRSourceAdded {
                    coord.addGOESIRLayer(on: mapView)
                } else {
                    coord.setGOESIRVisibility(true, on: mapView)
                }
            } else {
                coord.setGOESIRVisibility(false, on: mapView)
            }
        }

        // ── GOES Visible toggle ──
        if showGOESVis != coord.showGOESVis {
            coord.showGOESVis = showGOESVis
            if showGOESVis {
                if !coord.goesVisSourceAdded {
                    coord.addGOESVisLayers(on: mapView)
                } else {
                    coord.setGOESVisVisibility(true, on: mapView)
                }
            } else {
                coord.setGOESVisVisibility(false, on: mapView)
            }
        }

        // ── Wind Heatmap toggle ──
        if showWindHeatmap != coord.showWindHeatmap {
            coord.showWindHeatmap = showWindHeatmap
            if showWindHeatmap {
                if let snapshot = windSnapshot {
                    coord.updateWindHeatmap(snapshot: snapshot, on: mapView)
                }
            } else {
                coord.removeWindHeatmapLayer(from: mapView)
            }
        } else if showWindHeatmap, let snapshot = windSnapshot,
                  snapshot.validTime != coord.lastWindSnapshotTime {
            coord.updateWindHeatmap(snapshot: snapshot, on: mapView)
        }

        // ── Drawing mode toggle ──
        if isDrawing != coord.isDrawingModeActive {
            coord.setDrawingMode(isDrawing)
        }

        // ── Sync drawing annotations if version changed ──
        coord.syncDrawingAnnotations()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rulerState: rulerState, drawingState: drawingState, chartTileCache: chartTileCache, onStyleLoaded: onStyleLoaded)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        let rulerState: RulerState
        let drawingState: DrawingState
        let chartTileCache: ChartTileCacheService
        var onStyleLoaded: (() -> Void)?

        weak var mapViewRef: MapView?

        var styleLoadedCancelable: Cancelable?
        var cameraChangeCancelable: Cancelable?
        var currentStyleURI: StyleURI = MapConstants.style
        var lastResetNorthTrigger: Int = 0
        private var styleLoaded = false

        // Drawing state
        private var drawingGesture: UIPanGestureRecognizer?
        private var currentStrokeLayer: CAShapeLayer?
        private var currentScreenPoints: [CGPoint] = []
        private var currentGeoPoints: [CLLocationCoordinate2D] = []
        var isDrawingModeActive = false
        private var lastSyncedStrokeVersion: Int = -1
        private var annotationManager: PolylineAnnotationManager?

        // NEXRAD preloaded multi-layer system (24 frames, opacity-toggled)
        private static let nexradFrameCount = 24
        private var nexradSourceIds: [String] = []
        private var nexradLayerIds: [String] = []
        var activeNEXRADFrame: Int = -1
        var showNEXRAD = false
        var nexradSourceAdded = false

        // NOAA ENC Chart layer (CustomRasterSource with disk cache)
        private static let encSourceId = "noaa-enc"
        private static let encLayerId = "noaa-enc-layer"
        var showENC = false
        var encSourceAdded = false
        private var encRequiredTiles: Set<String> = []

        // GOES Satellite layers (Iowa Mesonet tile cache)
        private static let goesIRSourceId = "goes-ir"
        private static let goesIRLayerId = "goes-ir-layer"
        private static let goesVisEastSourceId = "goes-vis-east"
        private static let goesVisEastLayerId = "goes-vis-east-layer"
        private static let goesVisWestSourceId = "goes-vis-west"
        private static let goesVisWestLayerId = "goes-vis-west-layer"
        var showGOESIR = false
        var goesIRSourceAdded = false
        var showGOESVis = false
        var goesVisSourceAdded = false

        // Wind heatmap layer (ImageSource with geo-referenced UIImage)
        private static let windHeatmapSourceId = "wind-heatmap"
        private static let windHeatmapLayerId = "wind-heatmap-layer"
        var showWindHeatmap = false
        var windHeatmapSourceAdded = false
        var lastWindSnapshotTime: Date?

        // HRRR REFD preloaded multi-layer system (73 frames, opacity-toggled)
        private static let hrrrFrameCount = 73
        private var hrrrSourceIds: [String] = []
        private var hrrrLayerIds: [String] = []
        var activeHRRRFrame: Int = -1
        var showHRRR = false
        var hrrrSourceAdded = false

        // Ruler state
        private var rulerLineLayer: CAShapeLayer?
        private var rulerWingsLayer: CAShapeLayer?
        private var rulerDistanceLabel: PaddedLabel?
        private var rulerStartBearingLabel: PaddedLabel?
        private var rulerEndBearingLabel: PaddedLabel?
        private var rulerStartHandle: UIView?
        private var rulerEndHandle: UIView?
        var rulerLongPress: UILongPressGestureRecognizer?
        private var rulerDismissTap: UITapGestureRecognizer?
        private var rulerEndpointPan: UIPanGestureRecognizer?
        private var draggingEndpoint: RulerEndpoint?
        private let rulerHaptic = UIImpactFeedbackGenerator(style: .light)

        private enum RulerEndpoint { case start, end }

        init(rulerState: RulerState, drawingState: DrawingState, chartTileCache: ChartTileCacheService, onStyleLoaded: (() -> Void)?) {
            self.rulerState = rulerState
            self.drawingState = drawingState
            self.chartTileCache = chartTileCache
            self.onStyleLoaded = onStyleLoaded
        }

        // MARK: - Style Ready

        func styleDidLoad(mapView: MapView) {
            styleLoaded = true

            // Style reload destroys all sources/layers — reset tracking
            nexradSourceIds = []
            nexradLayerIds = []
            hrrrSourceIds = []
            hrrrLayerIds = []
            nexradSourceAdded = false
            hrrrSourceAdded = false
            encSourceAdded = false
            goesIRSourceAdded = false
            goesVisSourceAdded = false
            windHeatmapSourceAdded = false
            lastWindSnapshotTime = nil
            let prevNEXRADFrame = activeNEXRADFrame
            let prevHRRRFrame = activeHRRRFrame
            activeNEXRADFrame = -1
            activeHRRRFrame = -1

            // Notify SwiftUI that the map is ready
            DispatchQueue.main.async { [weak self] in
                self?.onStyleLoaded?()
            }

            // Create annotation manager for drawing strokes
            annotationManager = mapView.annotations.makePolylineAnnotationManager(id: "drawing-polylines")

            // Re-add layers if they were on before style reload
            if showENC {
                addENCLayer(on: mapView)
            }
            if showGOESIR {
                addGOESIRLayer(on: mapView)
            }
            if showGOESVis {
                addGOESVisLayers(on: mapView)
            }
            if showNEXRAD {
                preloadNEXRADLayers(on: mapView, initialFrame: max(prevNEXRADFrame, 0))
            }
            if showHRRR {
                preloadHRRRLayers(on: mapView, initialFrame: max(prevHRRRFrame, 0))
            }
        }

        // MARK: - NOAA ENC Chart Layer (CustomRasterSource + Disk Cache)
        //
        // Uses CustomRasterSource with ChartTileCacheService for cache-first
        // tile loading. Tiles come from NOAA's WMTS pre-rendered endpoint
        // (much faster than the old WMS on-the-fly rendering).
        //
        // Flow: Mapbox requests tile → check disk cache → serve cached OR
        //       fetch from NOAA WMTS → cache to disk → serve to Mapbox.

        /// Adds the NOAA ENC chart layer using CustomRasterSource for cache-first loading.
        func addENCLayer(on mapView: MapView) {
            guard styleLoaded else {
                print("[ENC] addENCLayer called but style not loaded yet")
                return
            }
            let map: MapboxMap = mapView.mapboxMap
            removeENCLayer(from: mapView)
            print("[ENC] Adding CustomRasterSource ENC layer...")

            let cache = chartTileCache

            let client = CustomRasterSourceClient.fromCustomRasterSourceTileStatusChangedCallback { [weak self, weak mapView] (tileID, status) in
                guard let self else {
                    print("[ENC] Callback: self is nil")
                    return
                }

                switch status {
                case .required:
                    let key = "\(tileID.z)/\(tileID.x)/\(tileID.y)"
                    self.encRequiredTiles.insert(key)
                    print("[ENC] Tile REQUIRED: \(key)")

                    Task { @MainActor in
                        guard let image = await cache.tile(z: Int(tileID.z), x: Int(tileID.x), y: Int(tileID.y)) else {
                            print("[ENC] Tile fetch FAILED: \(key)")
                            return
                        }
                        guard let mapView else {
                            print("[ENC] MapView nil, can't set tile: \(key)")
                            return
                        }

                        let tileData = CustomRasterSourceTileData(tileId: tileID, image: image)
                        do {
                            try mapView.mapboxMap.setCustomRasterSourceTileData(
                                forSourceId: Self.encSourceId,
                                tiles: [tileData]
                            )
                            print("[ENC] Tile SET: \(key) (\(image.size.width)x\(image.size.height))")
                        } catch {
                            print("[ENC] setTileData error: \(error)")
                        }
                    }

                case .notNeeded, .optional:
                    let key = "\(tileID.z)/\(tileID.x)/\(tileID.y)"
                    self.encRequiredTiles.remove(key)
                    cache.cancelTileFetch(z: Int(tileID.z), x: Int(tileID.x), y: Int(tileID.y))

                    if let mapView {
                        try? mapView.mapboxMap.setCustomRasterSourceTileData(
                            forSourceId: Self.encSourceId,
                            tiles: [CustomRasterSourceTileData(tileId: tileID, image: nil)]
                        )
                    }

                default:
                    break
                }
            }

            let options = CustomRasterSourceOptions(
                clientCallback: client,
                minZoom: 3,
                maxZoom: 16,
                tileSize: 256
            )

            let source = CustomRasterSource(id: Self.encSourceId, options: options)

            var layer = RasterLayer(id: Self.encLayerId, source: Self.encSourceId)
            layer.rasterOpacity = .constant(0.85)
            layer.rasterFadeDuration = .constant(0.3)
            layer.rasterResampling = .constant(.linear)

            do {
                try map.addSource(source)
                // Insert below HRRR/NEXRAD so weather overlays sit on top
                let belowLayer = hrrrLayerIds.first ?? nexradLayerIds.first
                if let belowId = belowLayer, (try? map.layer(withId: belowId)) != nil {
                    try map.addLayer(layer, layerPosition: .below(belowId))
                } else {
                    try map.addLayer(layer)
                }
                print("[ENC] Layer added successfully")
            } catch {
                print("[ENC] Failed to add layer: \(error)")
            }

            encSourceAdded = true
        }

        func setENCVisibility(_ visible: Bool, on mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.updateLayer(withId: Self.encLayerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(visible ? 0.85 : 0.0)
            }
        }

        private func removeENCLayer(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.removeLayer(withId: Self.encLayerId)
            try? map.removeSource(withId: Self.encSourceId)
            encRequiredTiles.removeAll()
            encSourceAdded = false
        }

        // MARK: - GOES Satellite Layers
        //
        // GOES East ABI CONUS B13 "Clean" IR (enhanced color) + GOES East & West Visible.
        // Iowa Mesonet tile cache — single live image, no frame scrubbing.
        // Layer ordering: above ENC, below HRRR/NEXRAD.

        func addGOESIRLayer(on mapView: MapView) {
            guard styleLoaded else { return }
            let map: MapboxMap = mapView.mapboxMap
            removeGOESIRLayer(from: mapView)

            var source = RasterSource(id: Self.goesIRSourceId)
            source.tiles = [
                "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/goes-east-ir-4km/{z}/{x}/{y}.png"
            ]
            source.tileSize = 256
            source.scheme = .xyz

            var layer = RasterLayer(id: Self.goesIRLayerId, source: Self.goesIRSourceId)
            layer.rasterOpacity = .constant(0.75)
            layer.rasterFadeDuration = .constant(0)
            layer.rasterResampling = .constant(.linear)

            do {
                try map.addSource(source)
                let belowLayer = hrrrLayerIds.first ?? nexradLayerIds.first
                if let belowId = belowLayer, (try? map.layer(withId: belowId)) != nil {
                    try map.addLayer(layer, layerPosition: .below(belowId))
                } else {
                    try map.addLayer(layer)
                }
                goesIRSourceAdded = true
            } catch {
                print("[GOES-IR] Failed to add layer: \(error)")
            }
        }

        func setGOESIRVisibility(_ visible: Bool, on mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.updateLayer(withId: Self.goesIRLayerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(visible ? 0.75 : 0.0)
            }
        }

        private func removeGOESIRLayer(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.removeLayer(withId: Self.goesIRLayerId)
            try? map.removeSource(withId: Self.goesIRSourceId)
            goesIRSourceAdded = false
        }

        func addGOESVisLayers(on mapView: MapView) {
            guard styleLoaded else { return }
            let map: MapboxMap = mapView.mapboxMap
            removeGOESVisLayers(from: mapView)

            // GOES East Visible
            var eastSource = RasterSource(id: Self.goesVisEastSourceId)
            eastSource.tiles = [
                "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/goes-east-vis-1km/{z}/{x}/{y}.png"
            ]
            eastSource.tileSize = 256
            eastSource.scheme = .xyz

            var eastLayer = RasterLayer(id: Self.goesVisEastLayerId, source: Self.goesVisEastSourceId)
            eastLayer.rasterOpacity = .constant(0.75)
            eastLayer.rasterFadeDuration = .constant(0)
            eastLayer.rasterResampling = .constant(.linear)

            // GOES West Visible
            var westSource = RasterSource(id: Self.goesVisWestSourceId)
            westSource.tiles = [
                "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/goes-west-vis-1km/{z}/{x}/{y}.png"
            ]
            westSource.tileSize = 256
            westSource.scheme = .xyz

            var westLayer = RasterLayer(id: Self.goesVisWestLayerId, source: Self.goesVisWestSourceId)
            westLayer.rasterOpacity = .constant(0.75)
            westLayer.rasterFadeDuration = .constant(0)
            westLayer.rasterResampling = .constant(.linear)

            do {
                let belowLayer = hrrrLayerIds.first ?? nexradLayerIds.first

                // West first (below), then East on top — East covers Gulf/FL area
                try map.addSource(westSource)
                if let belowId = belowLayer, (try? map.layer(withId: belowId)) != nil {
                    try map.addLayer(westLayer, layerPosition: .below(belowId))
                } else {
                    try map.addLayer(westLayer)
                }

                try map.addSource(eastSource)
                if let belowId = belowLayer, (try? map.layer(withId: belowId)) != nil {
                    try map.addLayer(eastLayer, layerPosition: .below(belowId))
                } else {
                    try map.addLayer(eastLayer)
                }

                goesVisSourceAdded = true
            } catch {
                print("[GOES-VIS] Failed to add layers: \(error)")
            }
        }

        func setGOESVisVisibility(_ visible: Bool, on mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            let opacity: Double = visible ? 0.75 : 0.0
            try? map.updateLayer(withId: Self.goesVisEastLayerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(opacity)
            }
            try? map.updateLayer(withId: Self.goesVisWestLayerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(opacity)
            }
        }

        private func removeGOESVisLayers(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.removeLayer(withId: Self.goesVisEastLayerId)
            try? map.removeSource(withId: Self.goesVisEastSourceId)
            try? map.removeLayer(withId: Self.goesVisWestLayerId)
            try? map.removeSource(withId: Self.goesVisWestSourceId)
            goesVisSourceAdded = false
        }

        // MARK: - Wind Heatmap Layer (ImageSource)
        //
        // Renders the WindFieldSnapshot as a small UIImage (16x16 pixels)
        // and places it on the map via Mapbox ImageSource. Mapbox's bilinear
        // resampling smooths the result at screen resolution.
        // Layer ordering: below ENC/HRRR/NEXRAD, above the base map.

        func updateWindHeatmap(snapshot: WindFieldSnapshot, on mapView: MapView) {
            guard styleLoaded else {
                print("[Wind] updateWindHeatmap called but style not loaded yet")
                return
            }

            guard let image = BeaufortInshoreRamp.heatmapImage(from: snapshot, alpha: 140) else {
                print("[Wind] Failed to generate heatmap image")
                return
            }

            // Write image to temp file — Mapbox ImageSource works reliably via URL
            guard let pngData = image.pngData() else {
                print("[Wind] Failed to encode heatmap PNG")
                return
            }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("wind_heatmap.png")
            do {
                try pngData.write(to: tempURL)
            } catch {
                print("[Wind] Failed to write heatmap temp file: \(error)")
                return
            }

            let map: MapboxMap = mapView.mapboxMap
            let bbox = snapshot.bbox

            // Coordinates: [top-left, top-right, bottom-right, bottom-left]
            // Each is [longitude, latitude]
            let coordinates: [[Double]] = [
                [bbox.minLon, bbox.maxLat],  // top-left (NW)
                [bbox.maxLon, bbox.maxLat],  // top-right (NE)
                [bbox.maxLon, bbox.minLat],  // bottom-right (SE)
                [bbox.minLon, bbox.minLat],  // bottom-left (SW)
            ]

            if windHeatmapSourceAdded {
                // Remove and re-add to update (reliable across Mapbox SDK versions)
                removeWindHeatmapLayer(from: mapView)
            }

            var source = ImageSource(id: Self.windHeatmapSourceId)
            source.coordinates = coordinates
            source.url = tempURL.absoluteString

            var layer = RasterLayer(id: Self.windHeatmapLayerId, source: Self.windHeatmapSourceId)
            layer.rasterOpacity = .expression(Exp(.interpolate) { Exp(.linear); Exp(.zoom); 8; 0.55; 12; 0.40; 15; 0.25 })
            layer.rasterFadeDuration = .constant(0.3)
            layer.rasterResampling = .constant(.linear)

            do {
                try map.addSource(source)
                // Insert below other overlays so it's the lowest overlay layer
                let belowLayer = encSourceAdded ? Self.encLayerId : (hrrrLayerIds.first ?? nexradLayerIds.first)
                if let belowId = belowLayer, (try? map.layer(withId: belowId)) != nil {
                    try map.addLayer(layer, layerPosition: .below(belowId))
                } else {
                    try map.addLayer(layer)
                }

                windHeatmapSourceAdded = true
                print("[Wind] Heatmap layer added successfully")
            } catch {
                print("[Wind] Failed to add heatmap layer: \(error)")
            }

            lastWindSnapshotTime = snapshot.validTime
        }

        func removeWindHeatmapLayer(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            try? map.removeLayer(withId: Self.windHeatmapLayerId)
            try? map.removeSource(withId: Self.windHeatmapSourceId)
            windHeatmapSourceAdded = false
            lastWindSnapshotTime = nil
        }

        // MARK: - NEXRAD Multi-Layer Preload System
        //
        // All 24 NEXRAD frames are preloaded as separate RasterSource + RasterLayer
        // pairs. Frame switching toggles rasterOpacity (0.0 ↔ 0.60) on just 2 layers
        // instead of swapping URLs — Mapbox keeps tiles in GPU/disk cache, giving
        // zero-flash, 60 fps loops identical to RadarScope's technique.

        /// Generates timestamps for all 24 NEXRAD frames.
        /// Index 0 = oldest (-120 min), index 23 = live.
        private func generateNEXRADTimestamps() -> [String] {
            var timestamps: [String] = []
            let now = Date()
            let fmt = DateFormatter()
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMddHHmm"
            let cal = Calendar.current

            for i in 0..<Self.nexradFrameCount {
                if i == Self.nexradFrameCount - 1 {
                    timestamps.append("")  // live
                } else {
                    let minutesAgo = (Self.nexradFrameCount - 1 - i) * 5
                    let date = now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
                    var comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
                    comps.minute = ((comps.minute ?? 0) / 5) * 5
                    comps.second = 0
                    if let rounded = cal.date(from: comps) {
                        timestamps.append(fmt.string(from: rounded))
                    } else {
                        timestamps.append("")
                    }
                }
            }
            return timestamps
        }

        private func nexradURL(forTimestamp timestamp: String) -> String {
            if timestamp.isEmpty {
                // Live frame — must use /cache/ (5-min server refresh)
                return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/ridge::USCOMP-N0Q-0/{z}/{x}/{y}.png"
            } else {
                // Historical — use /c/ endpoint (14-day cache)
                return "https://mesonet.agron.iastate.edu/c/tile.py/1.0.0/ridge::USCOMP-N0Q-\(timestamp)/{z}/{x}/{y}.png"
            }
        }

        /// Preloads all 24 NEXRAD frames as separate raster layers.
        func preloadNEXRADLayers(on mapView: MapView, initialFrame: Int) {
            guard styleLoaded else { return }
            let map: MapboxMap = mapView.mapboxMap
            removeAllNEXRADLayers(from: mapView)

            let timestamps = generateNEXRADTimestamps()

            for i in 0..<Self.nexradFrameCount {
                let sourceId = "nexrad-\(i)"
                let layerId = "nexrad-layer-\(i)"

                var source = RasterSource(id: sourceId)
                source.tiles = [nexradURL(forTimestamp: timestamps[i])]
                source.tileSize = 256
                source.scheme = .xyz

                var layer = RasterLayer(id: layerId, source: sourceId)
                layer.rasterOpacity = .constant(i == initialFrame ? 0.60 : 0.0)
                layer.rasterFadeDuration = .constant(0)
                layer.rasterResampling = .constant(.nearest)
                layer.rasterOpacityTransition = StyleTransition(duration: 0.15, delay: 0)

                do {
                    try map.addSource(source)
                    try map.addLayer(layer)
                } catch {
                    print("[NEXRAD] Failed to add frame \(i): \(error)")
                }
                nexradSourceIds.append(sourceId)
                nexradLayerIds.append(layerId)
            }

            nexradSourceAdded = true
            activeNEXRADFrame = initialFrame
        }

        /// Shows the specified NEXRAD frame by toggling opacity. Only updates 2 layers.
        func showNEXRADFrame(_ index: Int) {
            guard let mapView = mapViewRef, index != activeNEXRADFrame else { return }
            let map: MapboxMap = mapView.mapboxMap

            // Hide previous frame
            if activeNEXRADFrame >= 0, activeNEXRADFrame < nexradLayerIds.count {
                try? map.updateLayer(withId: nexradLayerIds[activeNEXRADFrame], type: RasterLayer.self) { layer in
                    layer.rasterOpacity = .constant(0.0)
                }
            }

            // Show new frame
            if index >= 0, index < nexradLayerIds.count {
                try? map.updateLayer(withId: nexradLayerIds[index], type: RasterLayer.self) { layer in
                    layer.rasterOpacity = .constant(0.60)
                }
            }

            activeNEXRADFrame = index
        }

        func setNEXRADVisibility(_ visible: Bool, on mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            if visible {
                // Restore active frame
                if activeNEXRADFrame >= 0, activeNEXRADFrame < nexradLayerIds.count {
                    try? map.updateLayer(withId: nexradLayerIds[activeNEXRADFrame], type: RasterLayer.self) { layer in
                        layer.rasterOpacity = .constant(0.60)
                    }
                }
            } else {
                // Hide all (keep sources alive so tiles stay in cache)
                for layerId in nexradLayerIds {
                    try? map.updateLayer(withId: layerId, type: RasterLayer.self) { layer in
                        layer.rasterOpacity = .constant(0.0)
                    }
                }
            }
        }

        private func removeAllNEXRADLayers(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            for i in 0..<nexradLayerIds.count {
                try? map.removeLayer(withId: nexradLayerIds[i])
                if i < nexradSourceIds.count {
                    try? map.removeSource(withId: nexradSourceIds[i])
                }
            }
            nexradLayerIds = []
            nexradSourceIds = []
            nexradSourceAdded = false
            activeNEXRADFrame = -1
        }

        // MARK: - HRRR REFD Multi-Layer Preload System
        //
        // Same technique as NEXRAD: all 73 forecast frames are preloaded.
        // Uses the /c/ endpoint (14-day cache) for forecast steps F0015+.

        private func hrrrURL(forFrame index: Int) -> String {
            let totalMinutes = index * 15
            let frame = String(format: "F%04d", totalMinutes)
            // HRRR forecasts are relative to the latest model run — must use /cache/
            return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/hrrr::REFD-\(frame)-0/{z}/{x}/{y}.png"
        }

        /// Preloads all 73 HRRR forecast frames as separate raster layers.
        func preloadHRRRLayers(on mapView: MapView, initialFrame: Int) {
            guard styleLoaded else { return }
            let map: MapboxMap = mapView.mapboxMap
            removeAllHRRRLayers(from: mapView)

            // Insert HRRR below NEXRAD if it exists
            let firstNEXRAD = nexradLayerIds.first

            for i in 0..<Self.hrrrFrameCount {
                let sourceId = "hrrr-\(i)"
                let layerId = "hrrr-layer-\(i)"

                var source = RasterSource(id: sourceId)
                source.tiles = [hrrrURL(forFrame: i)]
                source.tileSize = 256
                source.scheme = .xyz

                var layer = RasterLayer(id: layerId, source: sourceId)
                layer.rasterOpacity = .constant(i == initialFrame ? 0.55 : 0.0)
                layer.rasterFadeDuration = .constant(0)
                layer.rasterResampling = .constant(.nearest)
                layer.rasterOpacityTransition = StyleTransition(duration: 0.15, delay: 0)

                do {
                    try map.addSource(source)
                    if let nexradFirst = firstNEXRAD, (try? map.layer(withId: nexradFirst)) != nil {
                        try map.addLayer(layer, layerPosition: .below(nexradFirst))
                    } else {
                        try map.addLayer(layer)
                    }
                } catch {
                    print("[HRRR] Failed to add frame \(i): \(error)")
                }
                hrrrSourceIds.append(sourceId)
                hrrrLayerIds.append(layerId)
            }

            hrrrSourceAdded = true
            activeHRRRFrame = initialFrame
        }

        /// Shows the specified HRRR frame by toggling opacity. Only updates 2 layers.
        func showHRRRFrame(_ index: Int) {
            guard let mapView = mapViewRef, index != activeHRRRFrame else { return }
            let map: MapboxMap = mapView.mapboxMap

            // Hide previous frame
            if activeHRRRFrame >= 0, activeHRRRFrame < hrrrLayerIds.count {
                try? map.updateLayer(withId: hrrrLayerIds[activeHRRRFrame], type: RasterLayer.self) { layer in
                    layer.rasterOpacity = .constant(0.0)
                }
            }

            // Show new frame
            if index >= 0, index < hrrrLayerIds.count {
                try? map.updateLayer(withId: hrrrLayerIds[index], type: RasterLayer.self) { layer in
                    layer.rasterOpacity = .constant(0.55)
                }
            }

            activeHRRRFrame = index
        }

        func setHRRRVisibility(_ visible: Bool, on mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            if visible {
                if activeHRRRFrame >= 0, activeHRRRFrame < hrrrLayerIds.count {
                    try? map.updateLayer(withId: hrrrLayerIds[activeHRRRFrame], type: RasterLayer.self) { layer in
                        layer.rasterOpacity = .constant(0.55)
                    }
                }
            } else {
                for layerId in hrrrLayerIds {
                    try? map.updateLayer(withId: layerId, type: RasterLayer.self) { layer in
                        layer.rasterOpacity = .constant(0.0)
                    }
                }
            }
        }

        private func removeAllHRRRLayers(from mapView: MapView) {
            let map: MapboxMap = mapView.mapboxMap
            for i in 0..<hrrrLayerIds.count {
                try? map.removeLayer(withId: hrrrLayerIds[i])
                if i < hrrrSourceIds.count {
                    try? map.removeSource(withId: hrrrSourceIds[i])
                }
            }
            hrrrLayerIds = []
            hrrrSourceIds = []
            hrrrSourceAdded = false
            activeHRRRFrame = -1
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: - Drawing
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        private func configureDrawing() {
            guard let mapView = mapViewRef, drawingGesture == nil else { return }

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrawingGesture(_:)))
            gesture.maximumNumberOfTouches = 1
            gesture.minimumNumberOfTouches = 1
            gesture.isEnabled = false
            mapView.addGestureRecognizer(gesture)
            drawingGesture = gesture

            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            mapView.layer.addSublayer(layer)
            currentStrokeLayer = layer
        }

        func setDrawingMode(_ enabled: Bool) {
            guard let mapView = mapViewRef, enabled != isDrawingModeActive else { return }
            isDrawingModeActive = enabled

            if enabled { configureDrawing() }

            drawingGesture?.isEnabled = enabled

            // Toggle Mapbox pan between 1-finger and 2-finger
            if let mapPan = mapView.gestureRecognizers?.first(where: {
                $0 is UIPanGestureRecognizer && $0 !== drawingGesture && $0 !== rulerEndpointPan
            }) as? UIPanGestureRecognizer {
                mapPan.minimumNumberOfTouches = enabled ? 2 : 1
            }

            // Ruler and drawing are mutually exclusive
            if enabled {
                dismissRuler()
                rulerLongPress?.isEnabled = false
            } else {
                rulerLongPress?.isEnabled = true
            }
        }

        @objc private func handleDrawingGesture(_ gesture: UIPanGestureRecognizer) {
            guard let mapView = mapViewRef else { return }
            let map: MapboxMap = mapView.mapboxMap

            let screenPoint = gesture.location(in: mapView)
            let geoPoint = map.coordinate(for: screenPoint)

            switch gesture.state {
            case .began:
                currentScreenPoints = [screenPoint]
                currentGeoPoints = [geoPoint]

                currentStrokeLayer?.strokeColor = drawingState.isErasing
                    ? UIColor.white.withAlphaComponent(0.5).cgColor
                    : drawingState.selectedColor.uiColor.cgColor
                currentStrokeLayer?.lineWidth = drawingState.isErasing ? 3 : drawingState.selectedSize.rawValue

                updateCurrentStrokePath()

            case .changed:
                currentScreenPoints.append(screenPoint)
                currentGeoPoints.append(geoPoint)
                updateCurrentStrokePath()

            case .ended:
                if drawingState.isErasing {
                    eraseStrokesNearPath(screenPoints: currentScreenPoints)
                } else {
                    let stroke = Stroke(
                        coordinates: currentGeoPoints,
                        color: drawingState.selectedColor.uiColor,
                        lineWidth: drawingState.selectedSize.rawValue
                    )
                    drawingState.commitStroke(stroke)
                    syncDrawingAnnotations()
                }

                currentScreenPoints.removeAll()
                currentGeoPoints.removeAll()
                currentStrokeLayer?.path = nil

            case .cancelled, .failed:
                currentScreenPoints.removeAll()
                currentGeoPoints.removeAll()
                currentStrokeLayer?.path = nil

            default:
                break
            }
        }

        private func updateCurrentStrokePath() {
            guard currentScreenPoints.count >= 2 else {
                currentStrokeLayer?.path = nil
                return
            }
            currentStrokeLayer?.path = smoothPath(from: currentScreenPoints)
        }

        /// Catmull-Rom → cubic Bezier smoothing for professional-looking strokes.
        private func smoothPath(from points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            guard points.count >= 2 else { return path }

            if points.count == 2 {
                path.move(to: points[0])
                path.addLine(to: points[1])
                return path
            }

            path.move(to: points[0])
            let tension: CGFloat = 0.5
            let n = points.count

            for i in 0..<(n - 1) {
                let p0 = points[max(i - 1, 0)]
                let p1 = points[i]
                let p2 = points[min(i + 1, n - 1)]
                let p3 = points[min(i + 2, n - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / (6 * tension),
                    y: p1.y + (p2.y - p0.y) / (6 * tension)
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / (6 * tension),
                    y: p2.y - (p3.y - p1.y) / (6 * tension)
                )

                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }

            return path
        }

        private func eraseStrokesNearPath(screenPoints: [CGPoint]) {
            guard let mapView = mapViewRef else { return }
            let map: MapboxMap = mapView.mapboxMap
            let threshold: CGFloat = 20

            for stroke in drawingState.strokes.reversed() {
                let strokeScreenPoints = stroke.clCoordinates.map { map.point(for: $0) }
                for sp in strokeScreenPoints {
                    for ep in screenPoints {
                        let dx = sp.x - ep.x
                        let dy = sp.y - ep.y
                        if (dx * dx + dy * dy) <= threshold * threshold {
                            drawingState.eraseStroke(withID: stroke.id)
                            syncDrawingAnnotations()
                            return
                        }
                    }
                }
            }
        }

        func syncDrawingAnnotations() {
            guard let manager = annotationManager else { return }
            guard drawingState.strokeVersion != lastSyncedStrokeVersion else { return }
            lastSyncedStrokeVersion = drawingState.strokeVersion

            var annotations: [PolylineAnnotation] = []
            for stroke in drawingState.strokes {
                let coords = stroke.clCoordinates
                guard coords.count >= 2 else { continue }
                var annotation = PolylineAnnotation(lineCoordinates: coords)
                annotation.lineColor = StyleColor(stroke.uiColor)
                annotation.lineWidth = Double(stroke.lineWidth)
                annotations.append(annotation)
            }
            manager.annotations = annotations
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: - Ruler
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        private func configureRulerVisuals() {
            guard let mapView = mapViewRef, rulerLineLayer == nil else { return }

            // Dashed line
            let line = CAShapeLayer()
            line.fillColor = nil
            line.strokeColor = Theme.UIColors.rulerLine.cgColor
            line.lineWidth = 4.0
            line.lineDashPattern = [NSNumber(value: 10), NSNumber(value: 7)]
            line.lineCap = .round
            line.isHidden = true
            mapView.layer.addSublayer(line)
            rulerLineLayer = line

            // Wings (T-shape bars at endpoints)
            let wings = CAShapeLayer()
            wings.fillColor = nil
            wings.strokeColor = Theme.UIColors.rulerLine.cgColor
            wings.lineWidth = 4.0
            wings.lineCap = .round
            wings.isHidden = true
            mapView.layer.addSublayer(wings)
            rulerWingsLayer = wings

            // Labels
            rulerDistanceLabel = makeRulerLabel(on: mapView)
            rulerStartBearingLabel = makeRulerLabel(on: mapView)
            rulerEndBearingLabel = makeRulerLabel(on: mapView)

            // Handles
            rulerStartHandle = makeRulerHandle(on: mapView)
            rulerEndHandle = makeRulerHandle(on: mapView)

            // Tap to dismiss
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleRulerDismissTap(_:)))
            tap.numberOfTapsRequired = 1
            tap.isEnabled = false
            mapView.addGestureRecognizer(tap)
            rulerDismissTap = tap

            // Pan to reposition endpoints
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleRulerEndpointPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = false
            pan.delegate = self
            mapView.addGestureRecognizer(pan)
            rulerEndpointPan = pan
        }

        private func makeRulerLabel(on mapView: MapView) -> PaddedLabel {
            let label = PaddedLabel()
            label.textInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            label.font = Theme.UIColors.rulerFont
            label.textColor = .white
            label.backgroundColor = Theme.UIColors.rulerLabelBg
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.isHidden = true
            label.textAlignment = .center
            mapView.addSubview(label)
            return label
        }

        private func makeRulerHandle(on mapView: MapView) -> UIView {
            let hitArea = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            hitArea.backgroundColor = .clear
            hitArea.isHidden = true

            let circle = UIView(frame: CGRect(x: 16, y: 16, width: 12, height: 12))
            circle.backgroundColor = Theme.UIColors.rulerLabelBg
            circle.layer.cornerRadius = 6
            circle.layer.borderWidth = 2
            circle.layer.borderColor = Theme.UIColors.rulerLine.cgColor
            circle.isUserInteractionEnabled = false
            hitArea.addSubview(circle)

            mapView.addSubview(hitArea)
            return hitArea
        }

        // MARK: Ruler Gesture Handlers

        @objc func handleRulerLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = mapViewRef else { return }
            let map: MapboxMap = mapView.mapboxMap

            switch gesture.state {
            case .began:
                configureRulerVisuals()
                let p0 = gesture.location(ofTouch: 0, in: mapView)
                let p1 = gesture.location(ofTouch: 1, in: mapView)
                let c0 = map.coordinate(for: p0)
                let c1 = map.coordinate(for: p1)
                rulerState.update(start: c0, end: c1)
                showRulerElements(true)
                rulerDismissTap?.isEnabled = true
                rulerEndpointPan?.isEnabled = true
                rulerHaptic.prepare()
                updateRulerRendering()

            case .changed:
                guard gesture.numberOfTouches >= 2 else { return }
                let p0 = gesture.location(ofTouch: 0, in: mapView)
                let p1 = gesture.location(ofTouch: 1, in: mapView)
                let c0 = map.coordinate(for: p0)
                let c1 = map.coordinate(for: p1)
                rulerState.update(start: c0, end: c1)
                updateRulerRendering()

            case .ended:
                rulerHaptic.impactOccurred()

            case .cancelled, .failed:
                dismissRuler()

            default:
                break
            }
        }

        @objc private func handleRulerDismissTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapViewRef else { return }
            let point = gesture.location(in: mapView)
            if let startHandle = rulerStartHandle, !startHandle.isHidden {
                if startHandle.frame.contains(point) { return }
            }
            if let endHandle = rulerEndHandle, !endHandle.isHidden {
                if endHandle.frame.contains(point) { return }
            }
            dismissRuler()
        }

        @objc private func handleRulerEndpointPan(_ gesture: UIPanGestureRecognizer) {
            guard let mapView = mapViewRef else { return }
            let map: MapboxMap = mapView.mapboxMap

            switch gesture.state {
            case .began:
                let point = gesture.location(in: mapView)
                if let startHandle = rulerStartHandle, startHandle.frame.contains(point) {
                    draggingEndpoint = .start
                } else if let endHandle = rulerEndHandle, endHandle.frame.contains(point) {
                    draggingEndpoint = .end
                } else {
                    gesture.state = .failed
                    return
                }
                rulerHaptic.prepare()

            case .changed:
                let point = gesture.location(in: mapView)
                let coord = map.coordinate(for: point)
                switch draggingEndpoint {
                case .start:
                    rulerState.updateStart(coord)
                case .end:
                    rulerState.updateEnd(coord)
                case .none:
                    break
                }
                updateRulerRendering()

            case .ended:
                draggingEndpoint = nil
                rulerHaptic.impactOccurred()

            case .cancelled, .failed:
                draggingEndpoint = nil

            default:
                break
            }
        }

        // MARK: Ruler Rendering

        func updateRulerRendering() {
            guard rulerState.isVisible,
                  let startCoord = rulerState.startCoordinate,
                  let endCoord = rulerState.endCoordinate,
                  let mapView = mapViewRef else { return }

            let map: MapboxMap = mapView.mapboxMap
            let startPt = map.point(for: startCoord)
            let endPt = map.point(for: endCoord)

            // Dashed line path
            let path = CGMutablePath()
            path.move(to: startPt)
            path.addLine(to: endPt)
            rulerLineLayer?.path = path

            // Perpendicular direction
            let dx = endPt.x - startPt.x
            let dy = endPt.y - startPt.y
            let len = sqrt(dx * dx + dy * dy)
            let perpX: CGFloat
            let perpY: CGFloat
            if len > 0.001 {
                perpX = -dy / len
                perpY = dx / len
            } else {
                perpX = 0
                perpY = -1
            }

            // Wings — T-shape at each endpoint
            let wingLen: CGFloat = 60
            let wingsPath = CGMutablePath()
            wingsPath.move(to: CGPoint(x: startPt.x + perpX * wingLen, y: startPt.y + perpY * wingLen))
            wingsPath.addLine(to: CGPoint(x: startPt.x - perpX * wingLen, y: startPt.y - perpY * wingLen))
            wingsPath.move(to: CGPoint(x: endPt.x + perpX * wingLen, y: endPt.y + perpY * wingLen))
            wingsPath.addLine(to: CGPoint(x: endPt.x - perpX * wingLen, y: endPt.y - perpY * wingLen))
            rulerWingsLayer?.path = wingsPath

            // Label positioning
            let midPt = CGPoint(x: (startPt.x + endPt.x) / 2, y: (startPt.y + endPt.y) / 2)
            let offset: CGFloat = 24

            if let label = rulerDistanceLabel {
                label.text = rulerState.displayDistance
                label.sizeToFit()
                label.center = clampToScreen(CGPoint(x: midPt.x + perpX * offset, y: midPt.y + perpY * offset), size: label.bounds.size, in: mapView)
            }

            if let label = rulerStartBearingLabel {
                label.text = rulerState.forwardBearingDisplay
                label.sizeToFit()
                label.center = clampToScreen(CGPoint(x: startPt.x + perpX * offset, y: startPt.y + perpY * offset), size: label.bounds.size, in: mapView)
            }

            if let label = rulerEndBearingLabel {
                label.text = rulerState.reverseBearingDisplay
                label.sizeToFit()
                label.center = clampToScreen(CGPoint(x: endPt.x + perpX * offset, y: endPt.y + perpY * offset), size: label.bounds.size, in: mapView)
            }

            rulerStartHandle?.center = startPt
            rulerEndHandle?.center = endPt
        }

        private func clampToScreen(_ center: CGPoint, size: CGSize, in view: UIView) -> CGPoint {
            let margin: CGFloat = 8
            let halfW = size.width / 2
            let halfH = size.height / 2
            let bounds = view.bounds
            let x = min(max(center.x, margin + halfW), bounds.width - margin - halfW)
            let y = min(max(center.y, margin + halfH), bounds.height - margin - halfH)
            return CGPoint(x: x, y: y)
        }

        private func showRulerElements(_ visible: Bool) {
            let hidden = !visible
            rulerLineLayer?.isHidden = hidden
            rulerWingsLayer?.isHidden = hidden
            rulerDistanceLabel?.isHidden = hidden
            rulerStartBearingLabel?.isHidden = hidden
            rulerEndBearingLabel?.isHidden = hidden
            rulerStartHandle?.isHidden = hidden
            rulerEndHandle?.isHidden = hidden
        }

        private func dismissRuler() {
            guard rulerState.isVisible else { return }
            rulerState.clear()
            showRulerElements(false)
            rulerDismissTap?.isEnabled = false
            rulerEndpointPan?.isEnabled = false
            draggingEndpoint = nil
        }

        // MARK: Gesture Delegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === rulerEndpointPan && otherGestureRecognizer === rulerDismissTap { return true }
            if gestureRecognizer === rulerDismissTap && otherGestureRecognizer === rulerEndpointPan { return true }
            if gestureRecognizer === rulerLongPress { return false }
            return false
        }
    }
}

// MARK: - PaddedLabel

/// UILabel subclass with text insets for pill-style measurement labels.
final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets.zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(size)
        return CGSize(
            width: base.width + textInsets.left + textInsets.right,
            height: base.height + textInsets.top + textInsets.bottom
        )
    }
}
