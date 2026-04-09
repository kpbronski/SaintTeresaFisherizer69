import SwiftUI
@preconcurrency @_spi(Experimental) import MapboxMaps

// MARK: - Radar View

struct RadarView: View {

    @State private var rulerState = RulerState()
    @State private var drawingState = DrawingState()
    @State private var isDrawing = false
    @State private var showLayers = false
    @State private var useAerialMap = false
    @State private var showNEXRAD = false
    @State private var nexradFrameIndex = 23
    @State private var isPlaying = false
    @State private var showHRRR = false
    @State private var hrrrFrameIndex = 0
    @State private var showENC = false
    @State private var showGOESIR = false
    @State private var showGOESVis = false
    @State private var isHRRRPlaying = false
    @State private var resetNorthTrigger = 0
    @State private var mapStyleLoaded = false
    @State private var hasInitialized = false
    @State private var crabSpin: Double = 0
    @State private var chartTileCache = ChartTileCacheService()

    // Wind heatmap state
    @State private var showWindHeatmap = false
    @State private var windSnapshots: [WindFieldSnapshot] = []
    @State private var windCurrentHour: Int = 0
    @State private var windIsOffline = false
    @State private var windError: String?
    @State private var mapViewRef = MapViewReference()

    private var currentWindSnapshot: WindFieldSnapshot? {
        windSnapshots.isEmpty ? nil : windSnapshots[min(windCurrentHour, windSnapshots.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen Mapbox map with ruler + drawing
            RadarMapView(
                mapViewRef: mapViewRef,
                rulerState: rulerState,
                drawingState: drawingState,
                isDrawing: isDrawing,
                useAerialMap: useAerialMap,
                showNEXRAD: showNEXRAD,
                nexradFrameIndex: nexradFrameIndex,
                showHRRR: showHRRR,
                hrrrFrameIndex: hrrrFrameIndex,
                showENC: showENC,
                showGOESIR: showGOESIR,
                showGOESVis: showGOESVis,
                showWindHeatmap: showWindHeatmap,
                windSnapshot: currentWindSnapshot,
                resetNorthTrigger: resetNorthTrigger,
                chartTileCache: chartTileCache,
                onStyleLoaded: {
                    mapStyleLoaded = true
                }
            )
            .ignoresSafeArea()

            // Wind particle overlay — sits on top of the map in SwiftUI z-order
            if showWindHeatmap, !windSnapshots.isEmpty {
                WindParticleView(
                    snapshot: currentWindSnapshot,
                    mapViewProvider: { [mapViewRef] in mapViewRef.mapView }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Top header
            if !isDrawing && !rulerState.isVisible {
                VStack(spacing: 8) {
                    brandHeader

                    if showWindHeatmap {
                        WindOverlayBadge(
                            snapshot: currentWindSnapshot,
                            isOffline: windIsOffline
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            // Drawing toolbar slides in from top when active
            if isDrawing {
                DrawingToolbar(drawingState: drawingState) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDrawing = false
                    }
                    drawingState.save()
                }
                .padding(.horizontal, 8)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Ruler info badge (visible when ruler is active)
            if rulerState.isVisible {
                rulerInfoBadge
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isDrawing {
                toolButtons
                    .padding(.trailing, 12)
                    .padding(.top, 60)
            }
        }
        .overlay(alignment: .bottom) {
            if !isDrawing {
                VStack(spacing: 8) {
                    if showHRRR {
                        HRRRTimeSlider(
                            hrrrFrameIndex: $hrrrFrameIndex,
                            isPlaying: $isHRRRPlaying
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showNEXRAD {
                        RadarTimeSlider(
                            nexradFrameIndex: $nexradFrameIndex,
                            isPlaying: $isPlaying
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .overlay {
            if !hasInitialized {
                initLoadingOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            drawingState.load()
        }
        .task {
            // First-time init: wait for style + minimum 2s so the splash feels intentional
            guard !hasInitialized else { return }
            async let styleReady: () = waitForStyleLoad()
            async let minDelay: () = Task.sleep(for: .seconds(2))
            _ = await (styleReady, try? minDelay)
            withAnimation(.easeOut(duration: 0.5)) {
                hasInitialized = true
            }

            // Pre-fetch NOAA chart tiles for Big Bend region (zooms 7-12)
            // on first launch. Runs in background after map is ready.
            if !chartTileCache.hasPrefetchedBefore {
                await chartTileCache.prefetchBigBendRegion()
                chartTileCache.markPrefetchComplete()
            }
        }
        .sheet(isPresented: $showLayers) {
            layersSheet
        }
        .accessibilityLabel("Radar map centered on Big Bend Florida coast")
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        Text("CRAB LABS")
            .font(.system(size: 18, weight: .black, design: .monospaced))
            .foregroundStyle(Theme.teal)
            .shadow(color: Theme.teal.opacity(0.4), radius: 8)
            .padding(.top, 8)
    }

    // MARK: - Tool Buttons

    private var toolButtons: some View {
        VStack(spacing: 14) {
            // North / reset bearing button
            northButton

            toolButton(icon: "pencil.tip.crop.circle", label: "Draw") {
                withAnimation(.easeOut(duration: 0.2)) {
                    isDrawing = true
                }
            }

            toolButton(icon: "square.3.layers.3d", label: "Layers") {
                withAnimation(.easeOut(duration: 0.2)) {
                    showLayers.toggle()
                }
            }

            // Debug zoom indicator
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let zoom = mapViewRef.mapView?.mapboxMap.cameraState.zoom ?? 0
                Text("z\(zoom, specifier: "%.1f")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var northButton: some View {
        Button {
            resetNorthTrigger += 1
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            Circle()
                                .fill(Theme.deepGulf.opacity(0.6))
                        )
                        .overlay(
                            Circle()
                                .stroke(Theme.teal.opacity(0.3), lineWidth: 0.5)
                        )

                    VStack(spacing: 0) {
                        Text("N")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(Theme.teal)
                        // Small triangle pointer under the N
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Theme.teal.opacity(0.6))
                            .offset(y: -2)
                    }
                }
                .frame(width: 44, height: 44)

                Text("North")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.teal.opacity(0.6))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .accessibilityLabel("Reset map to face north")
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.teal)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                Circle()
                                    .fill(Theme.deepGulf.opacity(0.6))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Theme.teal.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.teal.opacity(0.6))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .accessibilityLabel(label)
    }

    // MARK: - Ruler Info Badge

    private var rulerInfoBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "ruler")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.teal)

            Text("2-finger press & drag to measure")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Capsule()
                        .fill(Theme.deepGulf.opacity(0.7))
                )
                .overlay(
                    Capsule()
                        .stroke(Theme.teal.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Layers Sheet

    private var layersSheet: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $useAerialMap) {
                        Label("Aerial Map", systemImage: "globe.americas.fill")
                    }
                    .tint(Theme.teal)
                } header: {
                    Text("Base Map")
                } footer: {
                    Text("Switches to satellite imagery with street labels.")
                }

                Section {
                    Toggle(isOn: $showNEXRAD) {
                        Label("Radar", systemImage: "circle.hexagongrid.fill")
                    }
                    .tint(Theme.teal)
                    .onChange(of: showNEXRAD) {
                        if showNEXRAD {
                            showHRRR = false
                            isHRRRPlaying = false
                        } else {
                            isPlaying = false
                        }
                    }

                    Toggle(isOn: $showHRRR) {
                        Label("Forecasted Radar", systemImage: "bolt.horizontal.fill")
                    }
                    .tint(.orange)
                    .onChange(of: showHRRR) {
                        if showHRRR {
                            showNEXRAD = false
                            isPlaying = false
                        } else {
                            isHRRRPlaying = false
                        }
                    }

                } header: {
                    Text("Radar")
                } footer: {
                    Text("Gold Standard of Radar.")
                }

                Section {
                    Toggle(isOn: $showGOESIR) {
                        Label("GOES IR (Enhanced)", systemImage: "cloud.sun.bolt.fill")
                    }
                    .tint(.purple)

                    Toggle(isOn: $showGOESVis) {
                        Label("GOES Visible", systemImage: "sun.max.fill")
                    }
                    .tint(.yellow)
                } header: {
                    Text("Satellite")
                } footer: {
                    Text("These are high quality images from space that help us keep an eye on those thunderheads building.")
                }

                Section {
                    Toggle(isOn: $showENC) {
                        Label("NOAA Nautical Chart", systemImage: "map.fill")
                    }
                    .tint(.cyan)

                    Toggle(isOn: $showWindHeatmap) {
                        Label("Wind Field", systemImage: "wind")
                    }
                    .tint(Color(hex: "2EA88A"))
                    .onChange(of: showWindHeatmap) {
                        if showWindHeatmap && windSnapshots.isEmpty {
                            Task { await fetchWindData() }
                        }
                    }
                } header: {
                    Text("Marine")
                } footer: {
                    Text("NOAA ENC data rendered with traditional chart symbology — depth contours, buoys, channels, and hazards. Wind field shows HRRR-derived surface winds color-coded by speed.")
                }
            }
            .navigationTitle("Map Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showLayers = false }
                        .foregroundStyle(Theme.teal)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Init Loading Overlay

    private var initLoadingOverlay: some View {
        ZStack {
            Theme.deepGulf.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("\u{1F980}")
                    .font(.system(size: 56))
                    .rotationEffect(.degrees(crabSpin))
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            crabSpin = 360
                        }
                    }

                Text("Hold onto your butts.")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text("INITIALIZING CRAB COMMAND")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.teal.opacity(0.5))
                    .tracking(2)
            }
        }
        .accessibilityLabel("Loading Crab Command radar")
    }

    private func waitForStyleLoad() async {
        while !mapStyleLoaded {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Wind Data Fetching

    private func fetchWindData() async {
        let service = WindDataService()
        windIsOffline = false
        windError = nil

        do {
            let snapshots = try await service.fetchSnapshots()
            windSnapshots = snapshots
            windCurrentHour = 0
            print("[Wind] Fetched \(snapshots.count) hourly snapshots")
        } catch {
            print("[Wind] Network fetch failed: \(error). Trying cache...")
            // Try offline cache
            do {
                let cached = try await service.loadCachedSnapshots()
                windSnapshots = cached
                windCurrentHour = 0
                windIsOffline = true
                print("[Wind] Loaded \(cached.count) cached snapshots (offline)")
            } catch {
                windError = error.localizedDescription
                print("[Wind] No cache available: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RadarView()
        .preferredColorScheme(.dark)
}
