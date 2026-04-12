import Foundation

/// Result of a batch upload attempt. `statusCode` is nil when the request
/// never completed (network failure, cancellation, etc).
struct RipplesUploadResult {
    let statusCode: Int?
    let error: Error?
}

/// HTTP client. Mirrors the PHP SDK: POSTs `{ "events": [...] }` to
/// `<host>/v1/ingest/batch` with a `Bearer <apiKey>` header.
final class RipplesApi {

    private let config: RipplesConfig
    private let session: URLSession

    init(_ config: RipplesConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.requestTimeout
        cfg.httpAdditionalHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "User-Agent": "ripples-ios/\(RipplesVersion.current)",
        ]
        self.session = URLSession(configuration: cfg)
    }

    func batch(events: [[String: Any]], completion: @escaping (RipplesUploadResult) -> Void) {
        guard let url = URL(string: config.host)?.appendingPathComponent("/v1/ingest/batch") else {
            completion(RipplesUploadResult(statusCode: nil, error: RipplesError.invalidHost))
            return
        }

        let body: [String: Any] = ["events": events]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(RipplesUploadResult(statusCode: nil, error: RipplesError.serialization))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.projectToken)", forHTTPHeaderField: "Authorization")

        session.uploadTask(with: request, from: data) { _, response, error in
            if let error = error {
                ripplesLog("Batch upload failed: \(error)")
                completion(RipplesUploadResult(statusCode: nil, error: error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode
            completion(RipplesUploadResult(statusCode: status, error: nil))
        }.resume()
    }
}

enum RipplesError: Error {
    case invalidHost
    case serialization
    case http(Int)
}
