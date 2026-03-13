import SwiftUI
import MapboxMaps

@main
struct SaintTeresaFisherizer69App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        MapboxOptions.accessToken = APIKeys.mapboxAccessToken

        // Generous tile cache — keeps radar frames in memory/disk across scrubbing
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,   // 64 MB
            diskCapacity:  256 * 1024 * 1024,    // 256 MB
            diskPath: "com.crablabs.tilecache"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App Delegate (Tab Bar & Scroll View Appearance)

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // ── Tab Bar: opaque dark background, no Liquid Glass ──
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.deepGulf)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        return true
    }

    // Lock to portrait only
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
