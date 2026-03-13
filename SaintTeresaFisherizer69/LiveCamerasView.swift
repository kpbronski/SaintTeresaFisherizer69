import SwiftUI

// MARK: - Camera Model

private struct Camera: Identifiable {
    let id = UUID()
    let name: String
    let imageURL: String
    let icon: String
}

// MARK: - Live Cameras View

struct LiveCamerasView: View {
    @State private var refreshToken = 0
    @State private var expandedCamera: Camera?

    // WeatherSTEM sky camera stations — Franklin & Wakulla County, FL
    // CDN format: https://cdn.weatherstem.com/skycamera/{county}/{station}/{camera_handle}/snapshot.jpg
    private static let cameras: [Camera] = [
        Camera(
            name: "Dog Island",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswndogisland/cumulus/snapshot.jpg",
            icon: "pawprint.fill"
        ),
        Camera(
            name: "Alligator Point",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnalligatorpoint/alligatorpointnw/snapshot.jpg",
            icon: "water.waves"
        ),
        Camera(
            name: "Ochlockonee Ramp",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnochlockonee/fswnochlockoneenorth/snapshot.jpg",
            icon: "ferry.fill"
        ),
        Camera(
            name: "FSU Marine Lab",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/fsucml/neptune/snapshot.jpg",
            icon: "building.columns.fill"
        ),
        Camera(
            name: "Island View Park",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/fswnislandviewpark/fswnislandviewparksouth/snapshot.jpg",
            icon: "binoculars.fill"
        ),
        Camera(
            name: "SGI Bridge",
            imageURL: "https://cdn.weatherstem.com/skycamera/franklin/sgibridge/sunrise/snapshot.jpg",
            icon: "bridge.fill"
        ),
        Camera(
            name: "St. Marks Lighthouse",
            imageURL: "https://cdn.weatherstem.com/skycamera/wakulla/fswnstmarks/stmarksrefuge/snapshot.jpg",
            icon: "lighthouse.fill"
        ),
        Camera(
            name: "Shell Point Beach",
            imageURL: "https://cdn.weatherstem.com/skycamera/wakulla/fswnspb/fswnspbeast/snapshot.jpg",
            icon: "beach.umbrella.fill"
        ),
        Camera(
            name: "Salinas Park",
            imageURL: "https://cdn.weatherstem.com/skycamera/gulf/fswnsalinaspark/cumulus/snapshot.jpg",
            icon: "mappin.and.ellipse"
        ),
    ]

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    headerSection

                    ForEach(Self.cameras) { camera in
                        cameraCard(camera)
                    }

                    footerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .refreshable {
                withAnimation(.easeInOut(duration: 0.3)) {
                    refreshToken += 1
                }
            }

            // Fullscreen overlay
            if let camera = expandedCamera {
                fullscreenOverlay(camera)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Live Cameras")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Franklin County Coastal Network")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.teal.opacity(0.5))
                Text("Pull down to refresh")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.top, 4)
    }

    // MARK: - Camera Card

    private func cameraCard(_ camera: Camera) -> some View {
        let url = URL(string: camera.imageURL)

        return VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Image(systemName: camera.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.teal.opacity(0.8))
                Text(camera.name.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.8)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.teal.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Separator
            Rectangle()
                .fill(Theme.teal.opacity(0.2))
                .frame(height: 0.5)

            // Camera image
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                case .failure:
                    failurePlaceholder
                case .empty:
                    loadingPlaceholder
                @unknown default:
                    loadingPlaceholder
                }
            }
            .id("\(camera.imageURL)-\(refreshToken)")
            .frame(height: 200)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
            )
        }
        .glassCard(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedCamera = camera
            }
        }
        .accessibilityLabel("\(camera.name) camera feed. Tap to enlarge.")
    }

    // MARK: - Fullscreen Overlay

    private func fullscreenOverlay(_ camera: Camera) -> some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedCamera = nil
                    }
                }

            VStack(spacing: 16) {
                // Title
                HStack(spacing: 8) {
                    Image(systemName: camera.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.teal)
                    Text(camera.name.uppercased())
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(1)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expandedCamera = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .accessibilityLabel("Close fullscreen view")
                }
                .padding(.horizontal, 20)

                // Full image
                AsyncImage(url: URL(string: camera.imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.windYellow.opacity(0.6))
                            Text("Feed Unavailable")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .empty:
                        ProgressView()
                            .tint(Theme.teal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
                .id("full-\(camera.imageURL)-\(refreshToken)")
                .padding(.horizontal, 12)

                Text("Tap anywhere to close")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Placeholders

    private var loadingPlaceholder: some View {
        ZStack {
            Theme.deepGulf
            ProgressView()
                .tint(Theme.teal.opacity(0.5))
        }
        .frame(height: 200)
    }

    private var failurePlaceholder: some View {
        ZStack {
            Theme.deepGulf
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.windYellow.opacity(0.6))
                Text("Feed Unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: 200)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Developed by Bronski Crab Labs")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.35))
            Text("WeatherSTEM Camera Network")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.top, 8)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        OceanBackgroundView()
    }
}

// MARK: - Preview

#Preview {
    LiveCamerasView()
        .preferredColorScheme(.dark)
}
