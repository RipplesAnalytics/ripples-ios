import Foundation

/// A small file-backed FIFO queue, modelled on PostHog's
/// `PostHogFileBackedQueue`: each event is a single file in a directory, the
/// in-memory list is just sorted filenames. This survives app restarts and
/// keeps memory pressure flat regardless of queue depth.
final class RipplesFileBackedQueue {

    let directory: URL
    private var items: [String] = []
    private let lock = NSLock()

    var depth: Int { lock.withLock { items.count } }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        let sorted = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }.map(\.lastPathComponent)

        lock.withLock { items = sorted }
    }

    func add(_ data: Data) {
        // Filename uses sortable timestamp + UUID so directory listing order
        // matches enqueue order even if mtime resolution collapses.
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            lock.withLock { items.append(filename) }
        } catch {
            ripplesLog("Failed to persist event: \(error)")
        }
    }

    func peek(_ count: Int) -> [Data] {
        let snapshot = lock.withLock { Array(items.prefix(count)) }
        var out: [Data] = []
        for name in snapshot {
            let url = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) {
                out.append(data)
            } else {
                // Corrupt or missing — drop it from the list so we don't loop.
                removeFile(name)
            }
        }
        return out
    }

    /// Remove the first `count` items (oldest first).
    func pop(_ count: Int) {
        let toRemove: [String] = lock.withLock {
            let n = min(count, items.count)
            let taken = Array(items.prefix(n))
            items.removeFirst(n)
            return taken
        }
        for name in toRemove {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Drop the oldest item. Used to enforce `maxQueueSize`.
    func dropOldest() {
        let removed: String? = lock.withLock {
            guard !items.isEmpty else { return nil }
            return items.removeFirst()
        }
        if let removed {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(removed))
        }
    }

    func clear() {
        lock.withLock {
            for name in items {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            items.removeAll()
        }
    }

    private func removeFile(_ name: String) {
        lock.withLock {
            if let idx = items.firstIndex(of: name) { items.remove(at: idx) }
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
