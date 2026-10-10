import AppKit
import CoreWLAN
import Foundation

/// AppKit-side Wi-Fi for the Mac Catalyst app. CoreWLAN is absent from the Catalyst SDK,
/// so the app loads this bundle and calls it through selectors with Foundation types only.
/// macOS names networks to CoreWLAN only after Location Services is allowed for the app.
/// Unchecked: Wi-Fi state is behind `lock`; title bar state is touched on the main actor only.
@objc(OPCMacWiFiBridge) final class MacWiFiBridge: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var cachedInterface: CWInterface?
    private var joinProcess: Process?
    private var titlebarColor: NSColor?
    private var observesWindows = false

    /// The Wi-Fi interface is fixed for the app's life; looking it up is an airportd round trip.
    private var interface: CWInterface? {
        lock.withLock {
            if cachedInterface == nil { cachedInterface = CWWiFiClient.shared().interface() }
            return cachedInterface
        }
    }

    @objc func currentSSID() -> NSString? { interface?.ssid() as NSString? }

    @objc func interfaceName() -> NSString? { interface?.interfaceName as NSString? }

    /// Blocking scan + associate. Returns nil on success, otherwise the reason.
    /// `byName` allows the `networksetup` fallback when CoreWLAN cannot name the network.
    @objc func join(_ request: NSDictionary) -> NSString? {
        guard let ssid = request["ssid"] as? String, !ssid.isEmpty else { return "No network name" }
        guard let interface else { return "This Mac has no Wi-Fi interface" }
        if interface.ssid() == ssid { return nil }
        let password = (request["password"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Without Location, airportd still matches the name but strips the SSID from the
        // result, and associating to that nameless network fails with -3900 (tmpErr).
        if let network = try? interface.scanForNetworks(withName: ssid)
            .filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue })
        {
            do {
                try interface.associate(to: network, password: password)
                return nil
            } catch {
                return error.localizedDescription as NSString
            }
        }
        guard (request["byName"] as? Bool) == true, let name = interface.interfaceName else {
            return "Allow Location for OpenPocketCine, or join \(ssid) from the Wi-Fi menu"
                as NSString
        }
        return joinByName(ssid, password: password, interface: name)
    }

    /// Stops a `networksetup` join in flight; CoreWLAN scans cannot be cancelled.
    @objc func cancelJoin() -> NSNumber {
        lock.withLock { joinProcess }?.terminate()
        return true
    }

    /// networksetup joins by name and needs no Location or administrator approval. The
    /// password is a process argument, visible to `ps` while it runs, so only the camera's
    /// own access point (credentials read over Bluetooth) takes this path.
    private func joinByName(_ ssid: String, password: String?, interface: String) -> NSString? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-setairportnetwork", interface, ssid] + (password.map { [$0] } ?? [])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return error.localizedDescription as NSString
        }
        lock.withLock { joinProcess = process }
        defer { lock.withLock { joinProcess = nil } }
        if exited.wait(timeout: .now() + 25) == .timedOut {
            process.terminate()
            exited.wait()
            return "Timed out joining \(ssid)" as NSString
        }
        if process.terminationReason == .uncaughtSignal { return "Join cancelled" }
        // Failures print a reason ("Could not find network …") and can still exit 0.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus == 0, text.isEmpty { return nil }
        return (text.isEmpty ? "Could not join \(ssid)" : text) as NSString
    }

    /// Catalyst draws content under a transparent title bar, so the traffic lights cover
    /// the monitor's top-left controls. A standard title bar keeps content below them.
    /// `color` is 0xRRGGBB. Windows opened later, or back from full screen, get it too.
    @MainActor @objc func useStandardTitlebars(_ color: NSNumber) -> NSNumber {
        let hex = color.uint32Value
        titlebarColor = NSColor(
            srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
        NSApplication.shared.windows.forEach(applyTitlebar)
        if !observesWindows {
            observesWindows = true
            let names = [NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification]
            for name in names {
                NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self?.applyTitlebar(window) }
                }
            }
        }
        return true
    }

    @MainActor private func applyTitlebar(_ window: NSWindow) {
        // Full screen has no title bar; the style is applied again on exit.
        guard window.styleMask.contains(.titled), !window.styleMask.contains(.fullScreen),
            let titlebarColor
        else { return }
        window.styleMask.remove(.fullSizeContentView)
        // Transparent over the window background: the bar reads as the app's dark canvas.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = titlebarColor
        window.titleVisibility = .hidden
    }

    /// Leaves `ssid` if this Mac is on it; macOS then rejoins a preferred network.
    @objc func leave(_ ssid: NSString) -> NSNumber {
        guard let interface, interface.ssid() == ssid as String else { return false }
        interface.disassociate()
        return true
    }
}
