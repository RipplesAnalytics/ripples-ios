import Foundation

/// Configuration for the Ripples SDK.
///
/// Mirrors the option surface of the PHP SDK: a key, an optional self-hosted
/// base URL, and queue/flush tuning. Defaults are tuned for mobile clients
/// (smaller batches, periodic flush, persistent queue across launches).
public final class RipplesConfig {

    public static let defaultHost = "https://api.ripples.sh"

    /// The publishable / secret key used to authenticate with the Ripples API.
    public let apiKey: String

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

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
