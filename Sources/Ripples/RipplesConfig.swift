import Foundation

/// Configuration for the Ripples SDK.
///
/// Uses the project's **public token** (a UUID) — the same one the web JS
/// SDK uses. It's safe to bundle in iOS apps: scoped to the write-only
/// `/v1/ingest` endpoints, and revenue events from the token are rejected
/// server-side to prevent MRR/LTV forgery from a scraped key. Rotate via
/// project settings if abuse is detected.
///
/// Never ship the server-side secret key (`priv_…`) in a client app.
public final class RipplesConfig {

    public static let defaultHost = "https://api.ripples.sh"

    /// Project token (UUID). Copy from your Ripples project settings.
    public let projectToken: String

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

    public init(projectToken: String) {
        // Assert in DEBUG if someone pastes the server secret into an app.
        // Not a runtime throw — a bad token 401s from the server anyway, and
        // crashing the host on init is worse than a log line.
        #if DEBUG
        if projectToken.hasPrefix("priv_") {
            assertionFailure("""
                Ripples: never ship a `priv_` secret key in a client app.
                Use the project token (UUID) from your project settings.
                """)
        }
        #endif
        self.projectToken = projectToken
    }
}
