import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Collects static device metadata and manages session lifecycle.
///
/// A new session starts on SDK init. After the app has been in the background
/// for ≥ 30 minutes, the session rotates on the next foreground resume.
final class RipplesContext {

    private static let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes

    private let lock = NSLock()
    private var _sessionId: String
    private var backgroundedAt: Date?

    /// Static device fields merged into every event.
    let device: [String: Any]

    init() {
        _sessionId = UUID().uuidString.lowercased()
        device = RipplesContext.collectDeviceInfo()
    }

    var sessionId: String {
        lock.withLock { _sessionId }
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
            }
            backgroundedAt = nil
        }
    }

    // MARK: - Device Info

    private static func collectDeviceInfo() -> [String: Any] {
        var ctx: [String: Any] = [
            "platform":         "ios",
            "sdk_name":         "ios",
            "sdk_version":      RipplesVersion.current,
            "device_brand":     "Apple",
            "language":         Locale.preferredLanguages.first ?? Locale.current.identifier,
            "client_timezone":  TimeZone.current.identifier,
        ]

        #if canImport(UIKit) && !os(watchOS)
        let dev = UIDevice.current
        ctx["os"]           = dev.systemName      // "iOS", "iPadOS"
        ctx["os_version"]   = dev.systemVersion   // "18.2"
        ctx["device_model"] = dev.model           // "iPhone", "iPad"

        switch dev.userInterfaceIdiom {
        case .phone:  ctx["device_type"] = "mobile"
        case .pad:    ctx["device_type"] = "tablet"
        case .mac:    ctx["device_type"] = "desktop"
        default:      ctx["device_type"] = "mobile"
        }

        // UIScreen.main must be accessed on the main thread.
        // setup() is almost always called from AppDelegate on the main thread,
        // so this will work in practice; if not, screen dims are omitted (default 0).
        if Thread.isMainThread {
            let bounds = UIScreen.main.bounds
            ctx["screen_width"]  = Int(bounds.width)
            ctx["screen_height"] = Int(bounds.height)
        }
        #elseif os(macOS)
        ctx["os"]           = "macOS"
        ctx["os_version"]   = ProcessInfo.processInfo.operatingSystemVersionString
        ctx["device_type"]  = "desktop"
        ctx["device_model"] = "Mac"
        #endif

        return ctx
    }
}
