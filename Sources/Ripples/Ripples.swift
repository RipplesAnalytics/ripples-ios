import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Public entry point to the Ripples SDK.
///
/// Usage:
///
///     Ripples.setup(RipplesConfig(apiKey: "priv_..."))
///     Ripples.shared.identify("user_123", traits: ["email": "jane@example.com"])
///     Ripples.shared.track("created a budget", userId: "user_123",
///                          properties: ["area": "budgets"])
///
/// The instance is process-wide. Events are persisted to disk and delivered
/// in batches; calls return immediately and never throw.
public final class Ripples {

    public static let shared = Ripples()

    private var config: RipplesConfig?
    private var api: RipplesApi?
    private var queue: RipplesQueue?
    private var storage: RipplesStorage?
    private var context: RipplesContext?
    private var visitorId: String?
    private let setupLock = NSLock()
    private var lifecycleObservers: [NSObjectProtocol] = []

    private init() {}

    /// Initialize the SDK. Safe to call multiple times — subsequent calls
    /// after the first are ignored.
    @discardableResult
    public static func setup(_ config: RipplesConfig) -> Ripples {
        shared.configure(config)
        return shared
    }

    private func configure(_ config: RipplesConfig) {
        setupLock.withLock {
            guard self.config == nil else {
                ripplesDebug("Ripples already initialized; ignoring setup()")
                return
            }
            self.config = config
            let storage = RipplesStorage(projectToken: config.projectToken)
            let api = RipplesApi(config)
            let reachability = RipplesReachability()
            let queue = RipplesQueue(config: config, api: api, storage: storage, reachability: reachability)
            let context = RipplesContext()

            // Restore or generate a persistent anonymous visitor ID.
            let storedId = storage.readString(.distinctId)
            let vid = storedId ?? UUID().uuidString.lowercased()
            if storedId == nil { storage.writeString(.distinctId, vid) }

            self.storage = storage
            self.api = api
            self.queue = queue
            self.context = context
            self.visitorId = vid

            queue.start()
            registerLifecycleObservers()
        }
    }

    // MARK: - Public API

    /// Set or update traits on a user. Extra keys become custom properties.
    public func identify(_ userId: String, traits: [String: Any] = [:]) {
        enqueue("identify", merging: ["user_id": userId], with: traits)
    }

    /// Track a product-usage event. `properties` may include `area`,
    /// `activated`, and any custom keys.
    public func track(_ actionName: String,
                      userId: String,
                      properties: [String: Any] = [:])
    {
        enqueue("track",
                merging: ["name": actionName, "user_id": userId],
                with: properties)
    }

    /// Force-flush the queue. The completion fires once the in-flight batch
    /// finishes (or immediately if the queue was empty / paused).
    public func flush(completion: (() -> Void)? = nil) {
        guard let queue = self.queue else { completion?(); return }
        if let completion = completion {
            queue.flushSync(completion: completion)
        } else {
            queue.flush()
        }
    }

    /// Internal — visible for tests.
    var queueDepth: Int { queue?.depth ?? 0 }

    /// Internal — visible for tests.
    func reset() {
        setupLock.withLock {
            queue?.stop()
            queue?.clear()
            for token in lifecycleObservers {
                NotificationCenter.default.removeObserver(token)
            }
            lifecycleObservers.removeAll()
            queue = nil
            api = nil
            storage = nil
            context = nil
            visitorId = nil
            config = nil
        }
    }

    // MARK: - Internals

    private func enqueue(_ type: String,
                         merging base: [String: Any],
                         with extras: [String: Any])
    {
        guard let queue = self.queue else {
            ripplesLog("SDK not initialized — call Ripples.setup() before sending events. Dropping '\(type)' call.")
            return
        }
        var props = base
        for (k, v) in extras { props[k] = v }

        // Inject persistent visitor ID (callers may override by supplying their own).
        if props["visitor_id"] == nil, let vid = visitorId {
            props["visitor_id"] = vid
        }

        // Inject session ID and device context without overwriting caller-supplied values.
        if let ctx = context {
            if props["session_id"] == nil {
                props["session_id"] = ctx.sessionId
            }
            for (k, v) in ctx.device where props[k] == nil {
                props[k] = v
            }
        }

        queue.add(RipplesEvent(type: type, properties: props))
    }

    private func registerLifecycleObservers() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default

        // Mark background time for session expiry tracking; also flush the queue.
        let backgroundToken = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.context?.didEnterBackground()
            self?.flush()
        }

        // Rotate session if the app was backgrounded long enough.
        let foregroundToken = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.context?.didBecomeActive() }

        let terminateToken = center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.flush() }

        lifecycleObservers = [backgroundToken, foregroundToken, terminateToken]
        #endif
    }
}
