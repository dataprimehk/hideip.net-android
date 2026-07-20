import Foundation
import Libbox
import Network
import NetworkExtension
import os.log

/// iOS packet tunnel that hosts the sing-box core (via Libbox), the
/// counterpart of Android's HideipVpnService.
///
/// The flow mirrors the Android service:
///  1. LibboxSetup() once with writable paths inside the app group container.
///  2. Create a CommandServer with the platform bridge as both the
///     PlatformInterface (so sing-box can ask us to open the TUN) and the
///     CommandServerHandler.
///  3. start() + startOrReloadService(configJson) boots the proxy.
///
/// The config JSON is handed over from the main app in the startTunnel
/// options and persisted to the app group container so the tunnel can also
/// be started from the system VPN toggle in Settings (no options there).
///
/// Status and traffic counters flow back to the main app through the app
/// group UserDefaults: the extension writes, the app's method channel reads.
/// The extension runs in its own process with a hard ~50 MB memory limit,
/// so the setup keeps logs small and pauses the core when the device sleeps.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private var statusClient: LibboxCommandClient?
    private lazy var bridge = PlatformBridge(self)
    private var setupDone = false

    // MARK: - Shared state (read by the main app)

    static let groupDefaults = UserDefaults(suiteName: TunnelShared.appGroup)

    private func setLastError(_ message: String?) {
        Self.groupDefaults?.set(message, forKey: TunnelShared.keyLastError)
    }

    private func resetStats() {
        for key in TunnelShared.statsKeys {
            Self.groupDefaults?.set(0, forKey: key)
        }
    }

    // MARK: - Lifecycle

    private func ensureSetup() throws {
        if setupDone { return }
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: TunnelShared.appGroup)
        else {
            throw TunnelError("App group container unavailable")
        }
        let base = container.appendingPathComponent("tunnel", isDirectory: true)
        let work = base.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let options = LibboxSetupOptions()
        options.basePath = base.path
        options.workingPath = work.path
        options.tempPath = NSTemporaryDirectory()
        // Keep the in-memory log ring small; the extension has a ~50 MB cap.
        options.logMaxLines = 100

        var error: NSError?
        LibboxSetup(options, &error)
        if let error { throw error }
        setupDone = true
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // The whole boot runs off the provider queue: startOrReloadService
        // calls back into openTun on its own stack, and openTun blocks on
        // setTunnelNetworkSettings whose completion must be free to arrive.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.startService(options: options)
                completionHandler(nil)
            } catch {
                self.setLastError(error.localizedDescription)
                self.stopService()
                completionHandler(error)
            }
        }
    }

    private func startService(options: [String: NSObject]?) throws {
        try ensureSetup()

        let config = try resolveConfig(options: options)

        // Validate before we try to run it, so we surface clean errors.
        var error: NSError?
        let server = LibboxNewCommandServer(bridge, bridge, &error)
        guard let server, error == nil else {
            throw error ?? TunnelError("Failed to create the command server")
        }
        try server.checkConfig(config)
        try server.start()
        try server.startOrReloadService(config, options: LibboxOverrideOptions())
        commandServer = server

        resetStats()
        startStatusClient()
        setLastError(nil)
    }

    /// The config comes from the app in the start options; the system VPN
    /// toggle in Settings starts us without options, so fall back to the last
    /// persisted config.
    private func resolveConfig(options: [String: NSObject]?) throws -> String {
        if let config = options?[TunnelShared.optionConfig] as? String, !config.isEmpty {
            try? config.write(to: persistedConfigURL(), atomically: true, encoding: .utf8)
            return config
        }
        if let config = try? String(contentsOf: persistedConfigURL(), encoding: .utf8),
           !config.isEmpty {
            return config
        }
        throw TunnelError("No configuration. Connect from the app first.")
    }

    private func persistedConfigURL() throws -> URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: TunnelShared.appGroup)
        else {
            throw TunnelError("App group container unavailable")
        }
        return container.appendingPathComponent("tunnel/config.json")
    }

    /// Subscribes to the core's status stream so we get live traffic counters.
    /// Failure here is non-fatal: the tunnel still works, we just show no stats.
    private func startStatusClient() {
        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandStatus)
        options.statusInterval = 1_000_000_000 // 1s, in nanoseconds
        guard let client = LibboxCommandClient(StatusHandler(), options: options) else {
            return
        }
        do {
            try client.connect()
            statusClient = client
        } catch {
            os_log("startStatusClient: %{public}@", error.localizedDescription)
        }
    }

    fileprivate func stopService() {
        if let client = statusClient {
            try? client.disconnect()
            statusClient = nil
        }
        resetStats()

        if let server = commandServer {
            try? server.closeService()
            // Give the core a moment to unwind before tearing the server down,
            // same as the reference client does.
            Thread.sleep(forTimeInterval: 0.1)
            server.close()
            commandServer = nil
        }
        bridge.reset()
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.stopService()
            completionHandler()
        }
    }

    // Keep the core quiet while the device sleeps; every megabyte counts
    // against the extension's memory cap.
    override func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        completionHandler()
    }

    override func wake() {
        commandServer?.wake()
    }

    /// Receives the status stream; we only care about the traffic numbers.
    private class StatusHandler: NSObject, LibboxCommandClientHandlerProtocol {
        func connected() {}
        func disconnected(_ message: String?) {}
        func writeStatus(_ message: LibboxStatusMessage?) {
            guard let message, let defaults = PacketTunnelProvider.groupDefaults else { return }
            defaults.set(message.uplink, forKey: TunnelShared.keyUplink)
            defaults.set(message.downlink, forKey: TunnelShared.keyDownlink)
            defaults.set(message.uplinkTotal, forKey: TunnelShared.keyUplinkTotal)
            defaults.set(message.downlinkTotal, forKey: TunnelShared.keyDownlinkTotal)
        }

        // Unused command channels; we only registered CommandStatus.
        func clearLogs() {}
        func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {}
        func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {}
        func write(_ events: LibboxConnectionEvents?) {}
        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
        func updateClashMode(_ newMode: String?) {}
        func setDefaultLogLevel(_ level: Int32) {}
    }
}

private struct TunnelError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// PlatformInterface + CommandServerHandler for the sing-box core, the iOS
/// counterpart of the same pair on HideipVpnService.
private class PlatformBridge: NSObject, LibboxPlatformInterfaceProtocol,
    LibboxCommandServerHandlerProtocol {
    private unowned let tunnel: PacketTunnelProvider
    private var pathMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - openTun

    /// sing-box hands us the addresses, routes and MTU it wants (from the tun
    /// inbound in the config, so MTU 1280 arrives here like on Android); we
    /// turn that into NEPacketTunnelNetworkSettings and give the core the
    /// packet flow's file descriptor.
    func openTun(_ options: LibboxTunOptionsProtocol?,
                 ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let ret0_ else {
            throw TunnelError("openTun: missing options")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        var dnsSettings: NEDNSSettings?
        if let dns = try? options.getDNSServerAddress(), !dns.value.isEmpty {
            let newDNS = NEDNSSettings(servers: [dns.value])
            settings.dnsSettings = newDNS
            dnsSettings = newDNS
        }

        var hasDefaultRoute = false
        if let inet4 = options.getInet4Address() {
            var addresses: [String] = []
            var masks: [String] = []
            while inet4.hasNext() {
                guard let prefix = inet4.next() else { break }
                addresses.append(prefix.address())
                masks.append(prefix.mask())
            }
            let ipv4 = NEIPv4Settings(addresses: addresses, subnetMasks: masks)
            var routes: [NEIPv4Route] = []
            if options.getAutoRoute() {
                let routeAddr = options.getInet4RouteAddress()
                if let routeAddr, routeAddr.hasNext() {
                    while routeAddr.hasNext() {
                        guard let prefix = routeAddr.next() else { break }
                        routes.append(NEIPv4Route(
                            destinationAddress: prefix.address(),
                            subnetMask: prefix.mask()))
                    }
                } else {
                    routes.append(NEIPv4Route.default())
                    hasDefaultRoute = true
                }
            }
            ipv4.includedRoutes = routes
            settings.ipv4Settings = ipv4
        }

        if let inet6 = options.getInet6Address() {
            var addresses: [String] = []
            var prefixes: [NSNumber] = []
            while inet6.hasNext() {
                guard let prefix = inet6.next() else { break }
                addresses.append(prefix.address())
                prefixes.append(NSNumber(value: prefix.prefix()))
            }
            if !addresses.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: addresses, networkPrefixLengths: prefixes)
                var routes: [NEIPv6Route] = []
                if options.getAutoRoute() {
                    let routeAddr = options.getInet6RouteAddress()
                    if let routeAddr, routeAddr.hasNext() {
                        while routeAddr.hasNext() {
                            guard let prefix = routeAddr.next() else { break }
                            routes.append(NEIPv6Route(
                                destinationAddress: prefix.address(),
                                networkPrefixLength: NSNumber(value: prefix.prefix())))
                        }
                    } else {
                        routes.append(NEIPv6Route.default())
                    }
                }
                ipv6.includedRoutes = routes
                settings.ipv6Settings = ipv6
            }
        }

        // Without a default route the resolver ignores our DNS unless the
        // settings claim every domain explicitly.
        if !hasDefaultRoute {
            dnsSettings?.matchDomains = [""]
        }

        // setTunnelNetworkSettings is async; openTun is called synchronously
        // from the core's own start stack, so block here until the settings
        // are applied (the completion arrives on a framework queue).
        let semaphore = DispatchSemaphore(value: 0)
        var settingsError: Error?
        tunnel.setTunnelNetworkSettings(settings) { error in
            settingsError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let settingsError { throw settingsError }

        // There is no public API for the tun fd; the packet flow owns one.
        // Reading it through KVC is the same approach the reference sing-box
        // client ships with, with a Libbox-side scan as the fallback.
        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fallback = LibboxGetTunnelFileDescriptor()
        if fallback != -1 {
            ret0_.pointee = fallback
            return
        }
        throw TunnelError("openTun: no tunnel file descriptor")
    }

    // MARK: - Interface monitoring

    // Unlike Android there is no protect(fd): the extension's own sockets
    // bypass its tunnel, so the core only needs to be told which physical
    // interface is current (auto_detect_interface must be fed here too).
    func usePlatformAutoDetectControl() -> Bool { false }

    func autoDetectControl(_ fd: Int32) throws {}

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        // Deliver the current path synchronously before returning so the core
        // never dials before it knows the underlying interface, then keep
        // feeding updates (WiFi to LTE handover and back).
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            Self.pushDefaultInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { path in
                Self.pushDefaultInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        semaphore.wait()
    }

    private static func pushDefaultInterface(
        _ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath
    ) {
        guard path.status != .unsatisfied,
              let interface = path.availableInterfaces.first
        else {
            listener.updateDefaultInterface(
                "", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(
            interface.name,
            interfaceIndex: Int32(interface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// sing-box's auto-detect resolves the bind interface against this list.
    /// Same rules as the Android implementation: exact Go net.Flags bits
    /// (Darwin's IFF_* values differ and must be translated) and IPv6 scope
    /// ids stripped, because Go cannot parse "fe80::1%en0".
    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        var byName: [String: (index: Int32, flags: Int32, addresses: [String])] = [:]
        var order: [String] = []

        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else {
            throw TunnelError("getifaddrs failed")
        }
        defer { freeifaddrs(ifap) }

        var cursor = ifap
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            if byName[name] == nil {
                let raw = Int32(bitPattern: entry.ifa_flags)
                var flags: Int32 = 0
                if raw & IFF_UP != 0 { flags |= 1 }            // net.FlagUp
                if raw & IFF_BROADCAST != 0 { flags |= 2 }     // net.FlagBroadcast
                if raw & IFF_LOOPBACK != 0 { flags |= 4 }      // net.FlagLoopback
                if raw & IFF_POINTOPOINT != 0 { flags |= 8 }   // net.FlagPointToPoint
                if raw & IFF_MULTICAST != 0 { flags |= 16 }    // net.FlagMulticast
                byName[name] = (Int32(if_nametoindex(name)), flags, [])
                order.append(name)
            }
            if let address = Self.numericAddress(entry.ifa_addr),
               let prefix = Self.prefixLength(entry.ifa_netmask) {
                byName[name]?.addresses.append("\(address)/\(prefix)")
            }
        }

        var interfaces: [LibboxNetworkInterface] = []
        for name in order {
            guard let info = byName[name] else { continue }
            let interface = LibboxNetworkInterface()
            interface.name = name
            interface.index = info.index
            interface.mtu = 1500
            interface.flags = info.flags
            interface.addresses = StringArrayIterator(info.addresses)
            interfaces.append(interface)
        }
        return InterfaceArrayIterator(interfaces)
    }

    private static func numericAddress(_ sa: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let sa else { return nil }
        let family = sa.pointee.sa_family
        guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                          nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let text = String(cString: host)
        // Strip any scope id (e.g. fe80::1%en0); Go can't parse it.
        if let percent = text.firstIndex(of: "%") {
            return String(text[..<percent])
        }
        return text
    }

    private static func prefixLength(_ sa: UnsafeMutablePointer<sockaddr>?) -> Int? {
        guard let sa else { return nil }
        var bits = 0
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            let mask = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            bits = UInt32(bigEndian: mask).nonzeroBitCount
        case AF_INET6:
            var addr = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr
            }
            withUnsafeBytes(of: &addr) { raw in
                for byte in raw { bits += byte.nonzeroBitCount }
            }
        default:
            return nil
        }
        return bits
    }

    // MARK: - Remaining PlatformInterface defaults (mirroring Android)

    func underNetworkExtension() -> Bool { true }

    func includeAllNetworks() -> Bool { false }

    func useProcFS() -> Bool { false }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?,
                             sourcePort: Int32, destinationAddress: String?,
                             destinationPort: Int32) throws -> LibboxConnectionOwner {
        // sing-box derefs the result; returning null crashes the core.
        // We don't do per-process routing in v1, so report "not found".
        throw TunnelError("process matching disabled")
    }

    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }

    func systemCertificates() -> LibboxStringIteratorProtocol? { nil }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func clearDNSCache() {}

    func send(_ notification: LibboxNotification?) throws {}

    // MARK: - CommandServerHandler

    func serviceReload() throws {}

    func serviceStop() throws {
        tunnel.stopService()
        tunnel.cancelTunnelWithError(nil)
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {}

    func writeDebugMessage(_ message: String?) {
        if let message { os_log("%{public}@", message) }
    }

    // MARK: - Iterator adapters

    private class StringArrayIterator: NSObject, LibboxStringIteratorProtocol {
        private let items: [String]
        private var position = 0
        init(_ items: [String]) { self.items = items }
        func hasNext() -> Bool { position < items.count }
        func next() -> String { defer { position += 1 }; return items[position] }
        func len() -> Int32 { Int32(items.count) }
    }

    private class InterfaceArrayIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private let items: [LibboxNetworkInterface]
        private var position = 0
        init(_ items: [LibboxNetworkInterface]) { self.items = items }
        func hasNext() -> Bool { position < items.count }
        func next() -> LibboxNetworkInterface? { defer { position += 1 }; return items[position] }
    }
}
