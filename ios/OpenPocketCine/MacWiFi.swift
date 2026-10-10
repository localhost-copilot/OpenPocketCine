#if targetEnvironment(macCatalyst)
    import Foundation

    /// Mac Catalyst stand-in for `NEHotspotConfiguration`, which macOS does not provide.
    /// Calls the embedded `OpenPocketCineMacBridge.bundle` (CoreWLAN) by selector.
    enum MacWiFi {
        enum Failure: LocalizedError {
            case unavailable
            case rejected(String)
            var errorDescription: String? {
                switch self {
                case .unavailable: "Mac Wi-Fi support is missing from this build."
                case .rejected(let reason): reason
                }
            }
        }

        private static let bridge: NSObject? = {
            guard
                let url = Bundle.main.builtInPlugInsURL?
                    .appendingPathComponent("OpenPocketCineMacBridge.bundle"),
                let type = Bundle(url: url)?.principalClass as? NSObject.Type
            else {
                ControlLiveLog.line("wifi: mac bridge bundle not loaded")
                return nil
            }
            return type.init()
        }()

        /// CoreWLAN scans and `networksetup` block for seconds; keep them off the
        /// Swift concurrency pool so decode and session tasks keep their threads.
        private static let joinQueue = DispatchQueue(label: "OpenPocketCine.MacWiFi.join")

        private static func call(_ selector: String, _ argument: Any? = nil) -> Any? {
            guard let bridge else { return nil }
            let sel = NSSelectorFromString(selector)
            let result =
                argument == nil ? bridge.perform(sel) : bridge.perform(sel, with: argument)
            return result?.takeUnretainedValue()
        }

        static var currentSSID: String? { call("currentSSID") as? String }
        /// The Wi-Fi interface does not change while the app runs.
        static let interfaceName: String? = call("interfaceName") as? String

        /// Scans and associates on `joinQueue`. `byName` allows the `networksetup`
        /// fallback (password on its command line) when Location is not allowed; only
        /// the camera's own access point uses it.
        static func join(ssid: String, password: String, byName: Bool = false) async throws {
            guard bridge != nil else { throw Failure.unavailable }
            let reason = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    joinQueue.async {
                        let request: NSDictionary = [
                            "ssid": ssid, "password": password, "byName": byName,
                        ]
                        continuation.resume(returning: call("join:", request) as? String)
                    }
                }
            } onCancel: {
                _ = call("cancelJoin")
            }
            try Task.checkCancellation()
            if let reason { throw Failure.rejected(reason) }
        }

        static func leave(ssid: String) { _ = call("leave:", ssid as NSString) }

        /// Moves window content below the traffic lights (main thread: AppKit windows).
        /// `color` is the 0xRRGGBB canvas the title bar shows.
        static func useStandardTitlebars(color: UInt32) {
            _ = call("useStandardTitlebars:", NSNumber(value: color))
        }
    }
#endif
