import Foundation

/// Configuration for the Ripples SDK.
///
/// Uses a **publishable** key (`pub_…`), not the server-side secret key
/// (`priv_…`). Publishable keys are safe to bundle in iOS apps: they're
/// scoped to the write-only `/v1/ingest` endpoints and cannot submit revenue
/// events (those are rejected server-side to prevent MRR/LTV forgery from a
/// scraped key). Rotate via the project dashboard if abuse is detected.
public final class RipplesConfig {

    public static let defaultHost = "https://api.ripples.sh"

    /// Publishable key for this project. Starts with `pub_`. Grab it from
    /// your Ripples project settings — never ship `priv_` keys in a client.
    public let publishableKey: String

    /// API base URL. Override for self-hosted installs.
    public var host: String = RipplesConfig.defaultHost

    /// Network request timeout in seconds.
    public var requestTimeout: TimeInterval = 10

    /// Periodic flush interval in seconds. Set to 0 to disable the timer.
    public var flushIntervalSeconds: TimeInterval = 30

    /// Flush as soon as the queue contains this many events.
    public var flushAt: Int = 20

    /// Maximum events delivered in a single batch request.
    public var maxBatchSize: Int = 50

    /// Maximum events held on disk. Oldest is evicted past this watermark.
    public var maxQueueSize: Int = 1000

    /// Optional callback for transport errors. Useful for host-app logging.
    public var onError: ((Error) -> Void)?

    /// Toggle verbose logs (off by default).
    public static var debugLogging: Bool = false

    public init(publishableKey: String) {
        // Warn loudly in debug if someone pastes a server secret into an app.
        // We don't throw — a malformed key gets rejected by the server anyway,
        // and crashing the host app on init is worse than a log line.
        #if DEBUG
        if publishableKey.hasPrefix("priv_") {
            assertionFailure("""
                Ripples: never ship a `priv_` secret key in a client app.
                Use the publishable `pub_` key from your project settings.
                """)
        }
        #endif
        self.publishableKey = publishableKey
    }
}
