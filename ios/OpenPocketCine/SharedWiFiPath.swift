import Foundation
import NetworkExtension

/// Current Wi-Fi IPv4 path for cameras joined to the operator's network.
enum SharedWiFiPath {
    static func validAddress(_ value: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return false }
        let first = UInt8(truncatingIfNeeded: UInt32(bigEndian: address.s_addr) >> 24)
        return first > 0 && first < 224 && first != 127
    }

    /// Joins this device to the operator's network and waits for its IPv4 address.
    /// Shared by Multiview and a saved camera's Wi-Fi setup.
    static func joinHost(ssid: String, password: String) async throws -> String? {
        #if targetEnvironment(macCatalyst)
            // Same acceptance as `joined()`: an unnamed network with an address (Wi-Fi
            // without Location, or Ethernet on the same LAN) is not re-joined.
            let current = MacWiFi.currentSSID
            if current != ssid, current != nil || address() == nil {
                try await MacWiFi.join(ssid: ssid, password: password)
            }
        #else
            if await WiFiJoiner.currentSSID() != ssid {
                try await applyJoin(ssid: ssid, password: password)
            }
        #endif
        // iOS applied the join. It names the network only with location permission (or
        // for networks this app configured); an unnamed Wi-Fi address is accepted too.
        func joined() async -> Bool {
            let current = await WiFiJoiner.currentSSID()
            return current == ssid || (current == nil && address() != nil)
        }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if await joined(), address() != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard await joined() else { return nil }
        return address()
    }

    private static func applyJoin(ssid: String, password: String) async throws {
        let config =
            password.isEmpty
            ? NEHotspotConfiguration(ssid: ssid)
            : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = false
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NEHotspotConfigurationManager.shared.apply(config) { error in
                if let error,
                    (error as NSError).code
                        != NEHotspotConfigurationError.alreadyAssociated.rawValue
                {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func address(hotspot: Bool = false) -> String? {
        interfaceAddress(netmask: false, hotspot: hotspot)
    }
    static func netmask(hotspot: Bool = false) -> String? {
        interfaceAddress(netmask: true, hotspot: hotspot)
    }

    private static func interfaceAddress(netmask: Bool, hotspot: Bool) -> String? {
        #if targetEnvironment(macCatalyst)
            // A Mac has no Personal Hotspot; its `bridge` interfaces are Internet Sharing
            // or virtual machines. Mac Wi-Fi is not always en0 (Ethernet often is); prefer
            // the Wi-Fi interface, then any wired one on the same LAN.
            guard !hotspot else { return nil }
            let wifi = MacWiFi.interfaceName
            return interfaceAddress(netmask: netmask) { $0 == wifi }
                ?? interfaceAddress(netmask: netmask) { $0.hasPrefix("en") }
        #else
            return interfaceAddress(netmask: netmask) {
                hotspot ? ($0.hasPrefix("bridge") || $0.hasPrefix("ap")) : $0 == "en0"
            }
        #endif
    }

    private static func interfaceAddress(
        netmask: Bool, matching matches: (String) -> Bool
    ) -> String? {
        let running = UInt32(IFF_UP | IFF_RUNNING)
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }
        var current = pointer
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard matches(String(cString: item.pointee.ifa_name)),
                item.pointee.ifa_flags & running == running,
                let host = item.pointee.ifa_addr.flatMap(numericIPv4),
                // 169.254 is self-assigned: no DHCP, so no camera reaches it.
                !host.hasPrefix("169.254.")
            else { continue }
            if !netmask { return host }
            if let mask = item.pointee.ifa_netmask.flatMap(numericIPv4) { return mask }
        }
        return nil
    }

    private static func numericIPv4(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        guard address.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard
            getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host,
                socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: host)
    }
}
