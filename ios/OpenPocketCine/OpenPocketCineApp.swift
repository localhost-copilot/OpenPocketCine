import MonitorUI
import SwiftUI

@main
struct OpenPocketCineApp: App {
    init() {
        #if DEBUG
            MultiviewUIReview.prepareIfRequested()
            ReliabilityReportingVerification.prepareIfRequested()
        #endif
        ReliabilityReporting.install()
        #if DEBUG
            ReliabilityReportingVerification.runIfRequested()
        #endif
        MonitorTheme.prepareResources()
        FeedStressAutomation.installIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            root
                .observeMonitorWindowGeometry()
                // iPad ignores Info.plist `UIStatusBarHidden` after launch unless
                // the hosting controller prefers it hidden. `~ipad` covers launch.
                .statusBarHidden(true)
                #if targetEnvironment(macCatalyst)
                    .onAppear(perform: Self.prepareMacWindows)
                #endif
        }
    }

    #if targetEnvironment(macCatalyst)
        /// A plain title bar holds the traffic lights above the monitor, without a title.
        private static func prepareMacWindows() {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.titlebar?.titleVisibility = .hidden
                scene.titlebar?.toolbar = nil
                scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
            }
            // The NSWindow exists once the first view appears.
            DispatchQueue.main.async {
                MacWiFi.useStandardTitlebars(color: MonitorTheme.backgroundHex)
            }
        }
    #endif

    @ViewBuilder private var root: some View {
        #if DEBUG
            if ReliabilityReportingVerification.mode != nil {
                Text("Reliability verification")
            } else if MultiviewUIReview.isActive {
                MultiviewUIReviewRoot()
            } else {
                AppRoot()
            }
        #else
            AppRoot()
        #endif
    }
}
