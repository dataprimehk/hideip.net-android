import Flutter
import NetworkExtension

/// Bridges Flutter <-> NETunnelProviderManager, the iOS counterpart of
/// MainActivity.kt.
///
/// Channel: net.hideip.vpn/control
///   prepare() -> saves the VPN profile; the first save shows the system
///                consent dialog. Returns true when allowed.
///   start(config, label) -> starts the PacketTunnel extension with the
///                sing-box config JSON
///   stop() -> stops the tunnel
///   status() -> {running, error}
///   stats() -> live traffic counters written by the extension
final class VpnChannel: NSObject {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "net.hideip.vpn/control", binaryMessenger: registrar.messenger())
        let instance = VpnChannel()
        channel.setMethodCallHandler { call, result in
            instance.handle(call, result: result)
        }
    }

    private var manager: NETunnelProviderManager?
    private let defaults = UserDefaults(suiteName: TunnelShared.appGroup)

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "prepare": prepare(result)
        case "start": start(call, result)
        case "stop": stop(result)
        case "status": status(result)
        case "stats": stats(result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    /// Answers on the main thread; NetworkExtension completions arrive on
    /// arbitrary queues and Flutter results must not.
    private func answer(_ result: @escaping FlutterResult, _ value: Any?) {
        DispatchQueue.main.async { result(value) }
    }

    // MARK: - prepare

    private func prepare(_ result: @escaping FlutterResult) {
        loadManager { manager in
            if let manager, manager.isEnabled {
                self.answer(result, true)
                return
            }
            // No profile yet (or another VPN disabled ours): (re)save it. The
            // first save is what shows the system "Allow VPN" dialog, so a
            // denial surfaces here as an error, which the app treats like a
            // cancelled consent on Android.
            let target = manager ?? Self.makeManager()
            target.isEnabled = true
            target.saveToPreferences { error in
                if error != nil {
                    self.answer(result, false)
                    return
                }
                // Reload after save; starting a freshly saved profile without
                // a reload is a known NetworkExtension failure.
                target.loadFromPreferences { _ in
                    self.manager = target
                    self.answer(result, true)
                }
            }
        }
    }

    private static func makeManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = TunnelShared.providerBundleId
        // Cosmetic; iOS shows it in Settings. The real server lives in the
        // sing-box config passed per start.
        proto.serverAddress = "hideip.net"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "hideip.net"
        return manager
    }

    private func loadManager(_ completion: @escaping (NETunnelProviderManager?) -> Void) {
        if let manager {
            completion(manager)
            return
        }
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let mine = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == TunnelShared.providerBundleId
            }
            self.manager = mine
            completion(mine)
        }
    }

    // MARK: - start / stop

    private func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?],
              let config = args["config"] as? String, !config.isEmpty
        else {
            result(FlutterError(code: "no_config", message: "config is required", details: nil))
            return
        }
        loadManager { manager in
            guard let manager else {
                self.answer(result, FlutterError(
                    code: "no_profile", message: "VPN profile missing; call prepare first",
                    details: nil))
                return
            }
            // A stale error from the previous session would trip the status
            // poll right after this start.
            self.defaults?.removeObject(forKey: TunnelShared.keyLastError)
            do {
                try manager.connection.startVPNTunnel(options: [
                    TunnelShared.optionConfig: config as NSString,
                ])
                self.answer(result, true)
            } catch {
                self.answer(result, FlutterError(
                    code: "start_failed", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func stop(_ result: @escaping FlutterResult) {
        loadManager { manager in
            manager?.connection.stopVPNTunnel()
            self.answer(result, true)
        }
    }

    // MARK: - status / stats

    private func status(_ result: @escaping FlutterResult) {
        loadManager { manager in
            // The Dart layer only knows running/not; report the transient
            // states as running so the optimistic connect isn't flipped back
            // by the first poll while the extension is still booting. A boot
            // failure lands as disconnected plus lastError a poll later.
            let running: Bool
            switch manager?.connection.status {
            case .connected, .connecting, .reasserting: running = true
            default: running = false
            }
            self.answer(result, [
                "running": running,
                "error": self.defaults?.string(forKey: TunnelShared.keyLastError) as Any,
            ])
        }
    }

    private func stats(_ result: @escaping FlutterResult) {
        func value(_ key: String) -> Int64 {
            defaults.map { Int64($0.integer(forKey: key)) } ?? 0
        }
        answer(result, [
            "uplink": value(TunnelShared.keyUplink),
            "downlink": value(TunnelShared.keyDownlink),
            "uplinkTotal": value(TunnelShared.keyUplinkTotal),
            "downlinkTotal": value(TunnelShared.keyDownlinkTotal),
        ])
    }
}
