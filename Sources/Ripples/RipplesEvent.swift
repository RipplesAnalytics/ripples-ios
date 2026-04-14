import Foundation

/// One serialized event in the queue, matching the wire format expected by
/// `POST /v1/ingest/batch` in the PHP SDK: a `type` discriminator, a
/// `sent_at` timestamp, and arbitrary top-level properties merged in.
struct RipplesEvent {

    let type: String
    let properties: [String: Any]
    let sentAt: Date
    /// Stable per-event UUID generated at enqueue time and persisted to disk.
    /// Survives retries so the server can deduplicate on `event_id`.
    let eventId: String

    init(type: String, properties: [String: Any], sentAt: Date = Date()) {
        self.type = type
        self.properties = properties
        self.sentAt = sentAt
        self.eventId = UUID().uuidString.lowercased()
    }

    func toJSON() -> [String: Any] {
        var json: [String: Any] = properties
        json["type"] = type
        json["sent_at"] = RipplesEvent.iso8601(sentAt)
        json["event_id"] = eventId
        return json
    }

    static func toData(_ event: RipplesEvent) -> Data? {
        let obj = sanitize(event.toJSON())
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj)
        else { return nil }
        return data
    }

    static func fromData(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Drop values that JSONSerialization can't encode (NSNull is fine; other
    /// non-Foundation types are coerced to their string form).
    private static func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = sanitize(v) }
            return out
        }
        if let arr = value as? [Any] {
            return arr.map(sanitize)
        }
        if JSONSerialization.isValidJSONObject([value]) || value is NSNull {
            return value
        }
        if let n = value as? NSNumber { return n }
        if let s = value as? String { return s }
        return String(describing: value)
    }
}
