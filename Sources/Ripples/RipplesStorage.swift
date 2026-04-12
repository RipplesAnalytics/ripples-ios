import Foundation

/// Resolves on-disk locations the SDK uses for its persistent queue and
/// any future durable state (e.g. an anonymous distinct id).
final class RipplesStorage {

    enum Key: String {
        case queue
        case distinctId = "distinct_id"
    }

    private let baseDir: URL

    init(apiKey: String) {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        // Scope to the apiKey so multiple Ripples instances don't collide.
        let safeKey = apiKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        baseDir = appSupport
            .appendingPathComponent("ripples", isDirectory: true)
            .appendingPathComponent(safeKey, isDirectory: true)

        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func url(for key: Key) -> URL {
        baseDir.appendingPathComponent(key.rawValue)
    }

    func readString(_ key: Key) -> String? {
        let url = self.url(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeString(_ key: Key, _ value: String) {
        try? value.data(using: .utf8)?.write(to: url(for: key), options: .atomic)
    }
}
