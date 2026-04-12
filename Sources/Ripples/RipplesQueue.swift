import Foundation

/// The brain of the offline pipeline.
///
/// Responsibilities, modelled on `PostHogQueue`:
///   * Persist events via `RipplesFileBackedQueue`.
///   * Flush periodically on a timer, immediately when `flushAt` is reached,
///     and again the moment reachability flips back online.
///   * Pause itself while offline or while the server has asked us to back off
///     (5xx / network error → exponential backoff).
///   * Serialize all flushes through a single dispatch queue to avoid double
///     sends.
final class RipplesQueue {

    private let config: RipplesConfig
    private let api: RipplesApi
    private let fileQueue: RipplesFileBackedQueue
    private let reachability: RipplesReachability?
    private let dispatchQueue = DispatchQueue(label: "sh.ripples.queue", qos: .utility)

    private let stateLock = NSLock()
    private var isFlushing = false
    private var pausedUntil: Date?
    private var retryCount: Int = 0
    private var timer: Timer?

    private let baseRetryDelay: TimeInterval = 5
    private let maxRetryDelay: TimeInterval = 5 * 60

    var depth: Int { fileQueue.depth }

    init(config: RipplesConfig,
         api: RipplesApi,
         storage: RipplesStorage,
         reachability: RipplesReachability?)
    {
        self.config = config
        self.api = api
        self.fileQueue = RipplesFileBackedQueue(directory: storage.url(for: .queue))
        self.reachability = reachability
    }

    func start() {
        reachability?.onChange = { [weak self] online in
            guard let self else { return }
            if online {
                ripplesLog("Network back online, flushing")
                self.flush()
            } else {
                ripplesLog("Network offline, queue paused")
            }
        }
        reachability?.start()

        if config.flushIntervalSeconds > 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.timer = Timer.scheduledTimer(
                    withTimeInterval: self.config.flushIntervalSeconds,
                    repeats: true
                ) { [weak self] _ in self?.flush() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reachability?.stop()
    }

    func add(_ event: RipplesEvent) {
        guard let data = RipplesEvent.toData(event) else {
            ripplesLog("Could not serialize event of type \(event.type)")
            return
        }

        if fileQueue.depth >= config.maxQueueSize {
            ripplesLog("Queue full (\(config.maxQueueSize)), dropping oldest")
            fileQueue.dropOldest()
        }

        fileQueue.add(data)
        ripplesLog("Queued '\(event.type)'. Depth=\(fileQueue.depth)")

        if fileQueue.depth >= config.flushAt {
            flush()
        }
    }

    func flush() {
        dispatchQueue.async { [weak self] in self?.drain() }
    }

    /// Synchronous drain — used by tests and by `Ripples.flush(completion:)`
    /// to give the host app a way to await delivery.
    func flushSync(completion: @escaping () -> Void) {
        dispatchQueue.async { [weak self] in
            self?.drain(completion: completion)
        }
    }

    func clear() { fileQueue.clear() }

    private func drain(completion: (() -> Void)? = nil) {
        let proceed: Bool = stateLock.withLock {
            if isFlushing { return false }
            if let until = pausedUntil, until > Date() { return false }
            if reachability?.isOnline == false { return false }
            isFlushing = true
            return true
        }

        guard proceed else { completion?(); return }

        let datas = fileQueue.peek(config.maxBatchSize)
        if datas.isEmpty {
            stateLock.withLock { isFlushing = false }
            completion?()
            return
        }

        let events = datas.compactMap { RipplesEvent.fromData($0) }
        let count = datas.count

        api.batch(events: events) { [weak self] result in
            guard let self else { completion?(); return }

            let status = result.statusCode ?? -1
            let success = (200 ... 299).contains(status)
            let retryable = status == -1 || (500 ... 599).contains(status) || status == 429

            if success {
                self.fileQueue.pop(count)
                self.stateLock.withLock {
                    self.retryCount = 0
                    self.isFlushing = false
                }
                ripplesLog("Flushed \(count) event(s)")
            } else if retryable {
                self.stateLock.withLock {
                    self.retryCount += 1
                    let delay = min(self.baseRetryDelay * Double(self.retryCount), self.maxRetryDelay)
                    self.pausedUntil = Date().addingTimeInterval(delay)
                    self.isFlushing = false
                }
                ripplesLog("Flush failed (status=\(status)), backing off")
                if let error = result.error { self.config.onError?(error) }
            } else {
                // 4xx other than 429: payload will never succeed, drop it so
                // a poison batch can't wedge the queue forever.
                self.fileQueue.pop(count)
                self.stateLock.withLock {
                    self.retryCount = 0
                    self.isFlushing = false
                }
                ripplesLog("Dropped \(count) event(s) due to non-retryable status \(status)")
                self.config.onError?(RipplesError.http(status))
            }

            completion?()
        }
    }
}
