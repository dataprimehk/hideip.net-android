import Foundation

/// Contract between the main app and the PacketTunnel extension. They run in
/// separate processes and share state through the app group UserDefaults:
/// the extension writes, the app's method channel reads.
enum TunnelShared {
    static let appGroup = "group.net.hideip.vpn"

    /// The provider bundle id the app addresses when saving the VPN profile.
    static let providerBundleId = "net.hideip.vpn.PacketTunnel"

    /// startTunnel option carrying the sing-box config JSON.
    static let optionConfig = "config"

    /// Last core error, shown by the app's status poll. Cleared on a
    /// successful start.
    static let keyLastError = "tunnel.lastError"

    // Live traffic counters. Rates are bytes/second, totals cumulative bytes
    // for the session; all zeroed on stop.
    static let keyUplink = "tunnel.uplink"
    static let keyDownlink = "tunnel.downlink"
    static let keyUplinkTotal = "tunnel.uplinkTotal"
    static let keyDownlinkTotal = "tunnel.downlinkTotal"

    static let statsKeys = [keyUplink, keyDownlink, keyUplinkTotal, keyDownlinkTotal]
}
