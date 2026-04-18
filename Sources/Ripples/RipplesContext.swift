import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Collects device metadata and manages session lifecycle.
///
/// Fields are split between a **static** context (captured once, never changes
/// over the process lifetime — app version, device model, OS, etc.) and a
/// **dynamic** context (recomputed on each event — screen size, timezone,
/// network type) so rotation and travel are reflected accurately.
///
/// Values are mapped onto the universal web+native schema where possible:
///   browser          ← app name (CFBundleName)
///   browser_version  ← app version (CFBundleShortVersionString)
///   engine           ← runtime name ("iOS" / "iPadOS" / "macOS")
///   engine_version   ← app build (CFBundleVersion)
///   hostname         ← bundle identifier
///
/// A new session starts on SDK init. After the app has been in the background
/// for ≥ 30 minutes, the session rotates on the next foreground resume.
final class RipplesContext {

    private static let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes

    private let lock = NSLock()
    private var _sessionId: String
    private var _sessionStartSent: Bool = false
    private var backgroundedAt: Date?

    /// Static fields merged into every event (top-level columns).
    let device: [String: Any]

    /// System flags stored in the `properties` Map under `$`-prefixed keys.
    /// `$`-prefixed keys are treated as system/SDK metadata and hidden from
    /// user-facing property displays (same convention as PostHog).
    /// TODO(db): promote to dedicated columns when dashboards need them:
    ///   $is_testflight, $is_emulator, $is_sideloaded, $is_mac_catalyst,
    ///   $is_ios_on_mac, $network_type, $app_build.
    let extras: [String: Any]

    private let screenSizeLock = NSLock()
    private var cachedScreenSize: CGSize?

    init() {
        _sessionId = UUID().uuidString.lowercased()
        device = RipplesContext.collectStaticContext()
        extras = RipplesContext.collectExtras()
        cachedScreenSize = RipplesContext.currentScreenSize()
        registerScreenObservers()
    }

    deinit {
        unregisterScreenObservers()
    }

    var sessionId: String {
        lock.withLock { _sessionId }
    }

    /// True if no screen view has been sent yet in the current session.
    var isFirstScreenInSession: Bool {
        lock.withLock { !_sessionStartSent }
    }

    /// Call after emitting a pageview with `session_start: true`.
    func markSessionStartSent() {
        lock.withLock { _sessionStartSent = true }
    }

    func didEnterBackground() {
        lock.withLock { backgroundedAt = Date() }
    }

    /// Rotates the session ID if the app was backgrounded for longer than the timeout.
    func didBecomeActive() {
        lock.withLock {
            if let bg = backgroundedAt,
               Date().timeIntervalSince(bg) >= RipplesContext.sessionTimeout {
                _sessionId = UUID().uuidString.lowercased()
                _sessionStartSent = false
            }
            backgroundedAt = nil
        }
    }

    // MARK: - Dynamic context

    /// Recomputed on every event — screen size may change on rotation,
    /// timezone on travel, network type on handoff between wifi/cellular.
    ///
    /// Keys are $-prefixed so user-supplied properties (e.g. a track() call
    /// with `platform="web"` to tag an event) can't accidentally collide
    /// with SDK-collected device context — the prefix reserves the namespace.
    func dynamic(networkType: String?) -> [String: Any] {
        var out: [String: Any] = [:]

        let size = screenSizeLock.withLock { cachedScreenSize }
        if let s = size {
            out["$screen_width"]   = Int(s.width)
            out["$screen_height"]  = Int(s.height)
            // On native there's no browser chrome — viewport == screen.
            out["$viewport_width"]  = Int(s.width)
            out["$viewport_height"] = Int(s.height)
        }

        let tz = TimeZone.current
        out["$client_timezone"] = tz.identifier
        // Match JS `Date.getTimezoneOffset()` convention: minutes, local→UTC
        // (e.g. Europe/Moscow UTC+3 → -180).
        out["$timezone_offset"] = -(tz.secondsFromGMT() / 60)

        if let n = networkType {
            out["$network_type"] = n // TODO(db): add column
        }
        return out
    }

    // MARK: - Static context

    private static func collectStaticContext() -> [String: Any] {
        var ctx: [String: Any] = [
            "$platform":        "ios",
            "$sdk_name":        "ios",
            "$sdk_version":     RipplesVersion.current,
            "$device_brand":    "Apple",
            "$language":        Locale.preferredLanguages.first ?? Locale.current.identifier,
            "$client_timezone": TimeZone.current.identifier,
            "$cpu_architecture": cpuArchitecture(),
        ]

        // App info → universal schema via browser/browser_version.
        let info = Bundle.main.infoDictionary
        if let appName = info?[kCFBundleNameKey as String] as? String
            ?? info?["CFBundleDisplayName"] as? String {
            ctx["$browser"] = appName
        }
        if let appVersion = info?["CFBundleShortVersionString"] as? String {
            ctx["$browser_version"] = appVersion
        }
        if let appBuild = info?["CFBundleVersion"] as? String {
            ctx["$engine_version"] = appBuild
        }
        if let bundleId = Bundle.main.bundleIdentifier {
            ctx["$hostname"] = bundleId
        }

        let runningOnMac = isMacCatalystApp || isIOSAppOnMac

        #if canImport(UIKit) && !os(watchOS)
        let dev = UIDevice.current

        // Real hardware model (e.g. "iPhone15,2") via sysctl, not generic "iPhone".
        ctx["$device_model"] = hardwareModel()

        if runningOnMac {
            ctx["$os"] = "macOS"
            ctx["$os_version"] = macOSVersionString()
            ctx["$device_type"] = "desktop"
            ctx["$engine"] = "macOS"
        } else {
            ctx["$os"] = dev.systemName                // "iOS", "iPadOS"
            ctx["$os_version"] = dev.systemVersion     // "18.2"
            ctx["$engine"] = dev.systemName

            switch dev.userInterfaceIdiom {
            case .phone:  ctx["$device_type"] = "mobile"
            case .pad:    ctx["$device_type"] = "tablet"
            case .mac:    ctx["$device_type"] = "desktop"
            case .tv:     ctx["$device_type"] = "tv"
            case .carPlay: ctx["$device_type"] = "carplay"
            default:      ctx["$device_type"] = "mobile"
            }
        }
        #elseif os(macOS)
        ctx["$os"] = "macOS"
        ctx["$os_version"] = macOSVersionString()
        ctx["$device_type"] = "desktop"
        ctx["$device_model"] = hardwareModel()
        ctx["$engine"] = "macOS"
        #endif

        return ctx
    }

    /// Flags sent but not (yet) column-mapped on the backend.
    private static func collectExtras() -> [String: Any] {
        var ex: [String: Any] = [
            "$is_emulator":     isSimulator,      // TODO(db): add column
            "$is_testflight":   isTestFlight,     // TODO(db): add column
            "$is_sideloaded":   isSideloaded,     // TODO(db): add column
            "$is_mac_catalyst": isMacCatalystApp, // TODO(db): add column
            "$is_ios_on_mac":   isIOSAppOnMac,    // TODO(db): add column
        ]
        if let info = Bundle.main.infoDictionary,
           let appBuild = info["CFBundleVersion"] as? String {
            ex["$app_build"] = appBuild // TODO(db): add column
        }
        return ex
    }

    // MARK: - Screen size tracking

    private static func currentScreenSize() -> CGSize? {
        #if canImport(UIKit) && !os(watchOS)
        guard Thread.isMainThread else {
            // Defer to main thread; observer will populate shortly.
            var result: CGSize?
            DispatchQueue.main.sync { result = UIScreen.main.bounds.size }
            return result
        }
        return UIScreen.main.bounds.size
        #else
        return nil
        #endif
    }

    private func registerScreenObservers() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(refreshScreenSize),
                           name: UIDevice.orientationDidChangeNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(refreshScreenSize),
                           name: UIWindow.didBecomeKeyNotification,
                           object: nil)
        #endif
    }

    private func unregisterScreenObservers() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    @objc private func refreshScreenSize() {
        #if canImport(UIKit) && !os(watchOS)
        let block = { [weak self] in
            guard let self else { return }
            let size = UIScreen.main.bounds.size
            self.screenSizeLock.withLock { self.cachedScreenSize = size }
        }
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
        #endif
    }

    // MARK: - Platform probes

    private static func hardwareModel() -> String {
        // On Catalyst / iOS-on-Mac "hw.machine" returns the underlying iPhone/iPad
        // model; "hw.model" returns the host Mac.
        var name = "hw.machine"
        #if targetEnvironment(macCatalyst)
        name = "hw.model"
        #else
        if #available(iOS 14.0, macOS 11.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
            name = "hw.model"
        }
        #endif
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private static func cpuArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #elseif arch(i386)
        return "i386"
        #else
        return ""
        #endif
    }

    private static func macOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    static let isMacCatalystApp: Bool = {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }()

    static let isIOSAppOnMac: Bool = {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
    }()

    /// App was installed via TestFlight (sandbox receipt).
    static let isTestFlight: Bool = {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
    }()

    /// App was sideloaded (ad-hoc, enterprise, dev). Embedded provisioning
    /// profiles are stripped by Apple on App Store / TestFlight distribution.
    static let isSideloaded: Bool = {
        if isSimulator { return false }
        #if targetEnvironment(macCatalyst)
        let ext = "provisionprofile"
        #else
        let ext = "mobileprovision"
        #endif
        return Bundle.main.path(forResource: "embedded", ofType: ext) != nil
    }()
}
