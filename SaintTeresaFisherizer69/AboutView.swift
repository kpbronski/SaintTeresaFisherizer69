import SwiftUI

// MARK: - About & Legal View

struct AboutView: View {

    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }()

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    dataSourcesCard
                    legalCard
                    footerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        OceanBackgroundView()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            // App icon — loaded from bundle since AppIcon.appiconset isn't available via UIImage(named:)
            if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String],
               let iconName = files.last,
               let icon = UIImage(named: iconName) {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Theme.teal.opacity(0.3), radius: 12)
            } else {
                // Fallback: crab emoji as placeholder
                Text("\u{1F980}")
                    .font(.system(size: 56))
                    .frame(width: 80, height: 80)
            }

            Text("STB Fisherizer 69")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text(appVersion)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.teal.opacity(0.6))

            Text("Coastal fishing forecast for Florida's Big Bend Coast")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    // MARK: - Data Sources

    private var dataSourcesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "DATA SOURCES", icon: "antenna.radiowaves.left.and.right")

            VStack(alignment: .leading, spacing: 10) {
                sourceRow(
                    name: "NOAA CO-OPS",
                    detail: "Tide predictions for 7 coastal stations from Dog Island Reef to Indian Pass",
                    url: "https://tidesandcurrents.noaa.gov"
                )
                sourceDivider()
                sourceRow(
                    name: "Open-Meteo",
                    detail: "16-day hourly wind, temperature, and precipitation forecasts (free, open-source API)",
                    url: "https://open-meteo.com"
                )
                sourceDivider()
                sourceRow(
                    name: "WeatherSTEM",
                    detail: "Live sensor data from FSWN stations across Franklin, Wakulla, and Gulf counties",
                    url: "https://weatherstem.com"
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Legal

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "LEGAL", icon: "doc.text")

            VStack(alignment: .leading, spacing: 12) {
                Text("This app provides forecast data for informational purposes only. Weather and tide predictions may be inaccurate. Always check official NOAA forecasts and exercise caution when boating or fishing.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://bronskicrablabs.com/privacy")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 12))
                        Text("Privacy Policy")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.teal)
                }

                Link(destination: URL(string: "https://bronskicrablabs.com/terms")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 12))
                        Text("Terms of Service")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.teal)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Developed by Bronski Crab Labs")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
            Text("Saint Teresa Beach, FL")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.teal)
            Text(title)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.teal)
                .tracking(1.2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func sourceRow(name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let link = URL(string: url) {
                Link(destination: link) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.teal.opacity(0.5))
                    }
                }
            } else {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceDivider() -> some View {
        Rectangle()
            .fill(Theme.teal.opacity(0.1))
            .frame(height: 0.5)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
        .preferredColorScheme(.dark)
}
