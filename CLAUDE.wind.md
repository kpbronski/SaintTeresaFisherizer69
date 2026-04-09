# CLAUDE.md — Fisherizer Wind Visualization Feature

> **NOTE TO KEVIN:** This file is feature-scoped context for Claude Code sessions working on the wind visualization. **Wipe or archive this before shipping** — it's development scaffolding, not production documentation. Suggested: rename to `CLAUDE.wind.md` and gitignore, or move to `docs/dev/` after the feature ships.

---

## What you're working on

Adding an animated, ForeFlight-inspired wind visualization to Fisherizer (Saint Teresa Fisherizer 69). The feature is a beta proving ground for visual techniques that will eventually graduate to Boatclaw. Fisherizer's job is to de-risk the visual layer with real TestFlight users before any of this touches the safety-critical Boatclaw codebase.

The full spec lives in `Fisherizer_Wind_Visualization_Handoff.md`. **Read it before starting any session.** This file is the persistent context layer; that file is the per-phase blueprint.

---

## Project context Claude should always know

- **App:** Saint Teresa Fisherizer 69, distributed via TestFlight to a small Big Bend / Alligator Harbor fishing community
- **Region:** ~20nm box around 29.9°N, 84.4°W (Alligator Harbor, St. Teresa, Dog Island, Cape San Blas, Apalachicola Bay)
- **Stack:** Swift 6 with strict concurrency, SwiftUI + UIKit bridge, Mapbox Maps SDK v11, Metal for the wind rendering
- **Map base:** Mapbox v11 — the wind layer attaches as a Mapbox custom layer (`CustomLayerHost` protocol) so it composites correctly with the map's z-order
- **Tide data:** NOAA station 8728311 (Alligator Harbor) is already wired up; the wind feature will eventually integrate with the existing tide UI in Phase 4 and Phase 5
- **No existing forecast scrubber** — Phase 5 builds one fresh, in Fisherizer's existing visual vocabulary

---

## Design north stars (do not violate)

1. **Polish, not "beta polish."** Fisherizer is small in scope but every shipped phase looks like a finished product. The Crab Nav / Dark Gulf Teal lineage is the aesthetic anchor.
2. **Inshore-first.** The decision space is 0–25kt, not 0–130kt. The `BeaufortInshoreRamp` reflects this and is the single source of truth for color across map AND chart.
3. **Honest about uncertainty.** Timestamp badge and plain-language summary are non-negotiable on every screen that shows wind data.
4. **Direction is a cognitive correction, not just a visualization.** Many users — including experienced boaters — read "E wind" as "wind moving east" when meteorological convention means "wind coming FROM the east, moving WEST." Every direction-bearing visual element in this feature must reinforce the *physically intuitive* reading: particles, ticks, and arrows all show the direction the air is *moving*, not the direction it's *from*. The "E" label stays for convention; everything else corrects the misconception. This is the core hypothesis Fisherizer is testing.
5. **Phase isolation.** The `WindFieldSnapshot` struct is the seam. Don't break it. Don't extend it without flagging.
6. **Visual coherence between map and chart.** When Phase 7 lands, the chart bars and the map flurries share a color language and a particle vocabulary so users transfer intuition between them.

---

## Architecture invariants

- `WindFieldSnapshot` is the data contract. Every layer of the system consumes or produces it.
- `WindDataService` is the only network actor. Nothing else fetches wind data.
- `BeaufortInshoreRamp` is a 1D Metal texture. Both map fragment shaders and chart-bar fragment shaders sample from the same ramp.
- Metal command buffers stay on a dedicated render queue. No `@MainActor` in hot rendering paths.
- Mapbox custom layer hosts the map wind layers. Do not bypass Mapbox's renderer — composite through it so the layer respects map gestures, zoom, and the existing layer stack.
- Total Metal allocation budget: ~25MB. If a phase pushes past that, flag it.

---

## Performance budget (enforce on every PR)

- 60fps on iPhone 12 with all layers active
- 120fps on ProMotion devices
- Battery draw <5%/hr foreground with wind layer active
- Cold launch with cached snapshot: same as current Fisherizer launch time, no regression
- No allocation hitches when toggling layers on/off

If a phase ships and any of these regress, the phase is not done.

---

## Do-not-touch list (every session)

- Existing Fisherizer tide UI (Phase 4 *integrates*, not rewrites)
- Existing fishing-conditions logic
- The Mapbox base style configuration
- Any Boatclaw code (this is Fisherizer)
- The TestFlight build pipeline / signing
- The `BeaufortInshoreRamp` color values without explicit Kevin approval — they are the cross-app standard

---

## Session hygiene (Kevin's standard practice)

- Clean checkpoint commit before starting any Claude Code session
- One phase per branch off `main`
- ECONNRESET = hard stop, restart Claude Code clean
- At the end of each session, update the "Phase status" section below with what landed and what didn't
- Leave the codebase in a buildable state at every commit

---

## Phase status

| Phase | Title | Status | Branch | Notes |
|-------|-------|--------|--------|-------|
| 1 | Data layer + static heatmap | **Shipped** | experiment/general | Open-Meteo 16x16 grid, Mapbox ImageSource heatmap, badge |
| 2 | Animated particles (basic) | **Stabilized** | experiment/general | Line-segment trails, bilinear quad mapping, custom Mercator projection |
| 3 | Gust encoding via stutter | Not started | — | |
| 4 | Tide layer + wind-vs-tide | Not started | — | NGOFS2 deferred to 4.5 |
| 5 | Forecast scrubber | Not started | — | Build fresh, no existing scrubber |
| 6 | Polish (tapered trails, Simplex, onboarding) | Not started | — | Tapered trails partially done in Phase 2 (line-segment approach) |
| 7 | Chart-bar flurries | Not started | — | Toggle/opt-in v1; cognitive correction goal; starts with Phase 7.0 spelunking |

Update this table at the end of each session.

---

## What shipped — architecture decisions for Boatclaw port

### Phase 1 — Data + Heatmap

**Files added:**
- `Models/WindFieldSnapshot.swift` — `WindFieldSnapshot`, `GeographicBoundingBox`, `WindDataError`
- `Services/WindDataService.swift` — actor, fetches 16x16 spatial grid from Open-Meteo, disk cache for offline
- `Utilities/BeaufortInshoreRamp.swift` — 7-stop color ramp, interpolated lookup, generates `UIImage` from snapshot
- `Views/WindOverlayBadge.swift` — source, valid time, age, plain-language summary, staleness/offline warnings

**Files modified:**
- `RadarMapView.swift` — wind heatmap as Mapbox `ImageSource` + `RasterLayer` with bilinear resampling, `MapViewReference` class for sharing map ref with SwiftUI siblings
- `RadarView.swift` — `showWindHeatmap` state, wind data fetch, "Wind Field" toggle in Layers sheet, badge overlay

**Boatclaw port notes:**
- `WindFieldSnapshot` contract ports intact — just change bbox and grid dims
- `WindDataService` uses Open-Meteo for simplicity; Boatclaw replaces with native HRRR/NOMADS (GRIB decode)
- Heatmap uses Mapbox `ImageSource` (not Metal) — writes 16x16 PNG to temp file, Mapbox bilinear-interpolates. Simple, reliable, correct visual. No Metal needed for the heatmap layer.
- `BeaufortInshoreRamp` is the single color truth — extend with offshore variant for Boatclaw
- Badge logic is reusable; summary generation is client-side from center-of-grid values

### Phase 2 — Animated Particles

**Files added:**
- `Views/WindParticleOverlay.swift` — `WindParticleView` (UIViewRepresentable) + `WindParticleCanvas` (UIView)

**Key architecture decision: line-segment trails, not accumulation buffer.**
The spec called for a framebuffer-fade (ping-pong accumulation texture) trail technique. We tried it — it breaks when the map camera moves because accumulated trails are in screen space and can't track geographic positions. The fix: each particle stores a position history (last 6 positions) and trails are drawn as tapered line segments each frame. No accumulation buffer, no ghosting, works at all zoom levels during pan/zoom.

**Phase 2 stabilization (shipped):**
- **Zoom-interpolated heatmap opacity:** `RasterLayer.rasterOpacity` uses Mapbox expression — 55% at z8, 40% at z12, 25% at z15. Fades gracefully as you zoom in.
- **BeaufortInshoreRamp saturation +15%:** HSL conversion, S×1.15 clamped to 1.0, back to RGB. Original hex values preserved in comment. Makes colors pop against dark map base.
- **Bilinear quad mapping:** Particle screen positions use bilinear interpolation through the 4 projected bbox corners (not axis-aligned bounding rect). This handles map rotation correctly — particles track the rotated heatmap quad.
- **Custom Mercator projection:** `MapboxMap.point(for:)` clamps off-screen points to (-1,-1) via an internal `.fit(to:)` call. At low zoom with rotation, bbox corners go off-screen and get clamped, producing a self-intersecting bowtie quad. Fix: custom Web Mercator projection that calibrates world scale from two on-screen points near the camera center, then projects all 4 corners without clamping. This is the correct long-term approach for any overlay that needs to project geographic coordinates to screen space.
- **Zoom-scaled particle count:** 800 at z<8, 1500 at z8-9, 2500 at z9-10.5, full 4000 at z10.5+. Reduces CPU load at low zoom where particles are dense in a small screen area.
- **UIGraphicsImageRenderer at 1x:** Replaced `UIGraphicsBeginImageContextWithOptions` with `UIGraphicsImageRenderer` (format.scale = 1.0). The renderer handles coordinate space correctly; 1x scale keeps perf manageable. Diagnostic debug flag (`debugDrawHeatmapQuad`) left in place for future regression testing.

**Boatclaw port notes:**
- The line-segment trail approach is the one that works for map-integrated rendering. Don't re-attempt accumulation buffers unless the renderer is in geographic space (e.g., a Metal CustomLayerHost that transforms in the vertex shader).
- Particle overlay is a SwiftUI `UIViewRepresentable` overlaid on top of the MapView in a ZStack — NOT a subview of MapView (Mapbox's Metal layer renders over subviews).
- `MapViewReference` class is the bridge — RadarMapView populates it in `makeUIView`, particle overlay reads it each frame.
- **DO NOT use `MapboxMap.point(for:)` for overlay projection.** It clamps off-screen points to (-1,-1). Use the custom Mercator projection from `WindParticleCanvas.projectCorners()` instead. This is calibrated each frame via two on-screen points near the camera center.
- 4,000 particles at 60fps via Core Graphics is workable but at the CPU ceiling. Metal compute is the real answer for 50K+ particles or tapered geometry (Phase 6).
- Particle speed math: U/V (m/s) → degrees/sec → normalized-bbox-fraction/frame. The `96_000` and `111_000` constants are meters-per-degree at 30°N latitude. Boatclaw covering larger areas needs proper Mercator correction instead of this flat-earth approximation.

---

## Open questions Claude should not invent answers to

- The existing Fisherizer wind/tide chart is **not Swift Charts and not straightforward custom SwiftUI** — it is "something else." Phase 7 starts with a mandatory spelunking sub-step (Phase 7.0) where Claude reads the existing chart implementation and writes a one-page summary for Kevin before any rendering work begins.
- Exact Fisherizer chart bar dimensions (Kevin to confirm during Phase 7.0)
- Whether to migrate to native HRRR via NOMADS in Fisherizer or hold that for the Boatclaw port (current default: hold)
- A/B feedback from the Phase 4 wind-vs-tide visualization style toggle (will inform what graduates to Boatclaw)
- Whether the Phase 7 toggle adoption data justifies promoting flurries to the default chart style in a future release

When you hit one of these, ask Kevin. Don't guess.

---

## Reference materials

- `Fisherizer_Wind_Visualization_Handoff.md` — the full per-phase spec with acceptance criteria
- `ForeFlight_Wind_Visualization_For_Apps.pdf` — Kevin's consulting report; the technical bible for the GPU shader work
- ForeFlight Dynamic Winds reference screenshot — visual target for the map version
- Mapbox custom layer docs: https://docs.mapbox.com/ios/maps/api/11.0.0/Classes/CustomLayer.html
- Open-Meteo HRRR endpoint docs: https://open-meteo.com/en/docs/historical-weather-api

---

## If something feels wrong

Stop, surface it to Kevin. The "I'll just refactor this real quick" instinct is exactly the kind of scope creep this file exists to prevent. Kevin's working pattern is: architect collaboratively, hand a tightly-scoped spec to Claude Code, expect that spec to be executed faithfully. Out-of-scope refactors break the model.
