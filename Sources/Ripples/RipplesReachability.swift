import Foundation
import Network

/// Thin wrapper around `NWPathMonitor` that publishes online/offline edges.
/// Used to pause the queue when there's no connectivity and to kick a flush
/// the moment we come back online.
final class RipplesReachability {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "sh.ripples.reachability")
    private(set) var isOnline: Bool = true

    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            let changed = online != self.isOnline
            self.isOnline = online
            if changed { self.onChange?(online) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
