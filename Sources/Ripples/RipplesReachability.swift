import Foundation
import Network

/// Thin wrapper around `NWPathMonitor` that publishes online/offline edges.
/// Used to pause the queue when there's no connectivity and to kick a flush
/// the moment we come back online.
final class RipplesReachability {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "sh.ripples.reachability")
    private let stateLock = NSLock()
    private var _isOnline: Bool = true
    private var _networkType: String?

    var isOnline: Bool {
        stateLock.withLock { _isOnline }
    }

    /// Last observed interface type: "wifi", "cellular", "wired", "other", or nil when offline.
    var networkType: String? {
        stateLock.withLock { _networkType }
    }

    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            let type: String? = online ? RipplesReachability.classify(path) : nil
            let wasOnline = self.stateLock.withLock { () -> Bool in
                let prev = self._isOnline
                self._isOnline = online
                self._networkType = type
                return prev
            }
            if online != wasOnline { self.onChange?(online) }
        }
        monitor.start(queue: queue)
    }

    private static func classify(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi)     { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    func stop() {
        monitor.cancel()
    }
}
