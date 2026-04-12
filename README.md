# Ripples iOS SDK

iOS / macOS / tvOS / watchOS client for [Ripples.sh](https://ripples.sh).
Mirrors the [`ripples-php`](../ripples-php) wire format (`POST /v1/ingest/batch`,
`Bearer` auth) and adopts the offline-first patterns of the PostHog iOS SDK:
file-backed queue, `NWPathMonitor` reachability, periodic + threshold + lifecycle
flushes, and exponential backoff on transient failures.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/ripples-sh/ripples-ios", from: "0.1.0")
```

## Keys

Ripples issues two keys per project:

| Key        | Prefix  | Where to use              | Scope                                     |
|------------|---------|---------------------------|-------------------------------------------|
| Secret     | `priv_` | Server-side only          | Full ingest access, incl. `revenue`       |
| Publishable| `pub_`  | iOS / browser / any client| `track`, `identify`, `signup` only        |

The iOS SDK takes the **publishable** key. It's safe to bundle in your app:
revenue events from `pub_` keys are rejected server-side, so a scraped key
can't forge your MRR / LTV numbers. If you see abuse, rotate the key in
project settings.

**Never** ship the `priv_` key in a mobile or web app.

## Usage

Initialize once at app launch:

```swift
import Ripples

Ripples.setup(RipplesConfig(publishableKey: "pub_your_publishable_key"))
```

Then, anywhere:

```swift
Ripples.shared.identify("user_123", traits: [
    "email": "jane@example.com",
    "name":  "Jane Smith",
])

Ripples.shared.track("created a budget", userId: "user_123", properties: [
    "area": "budgets",
])

// Mark this specific occurrence as the activation moment.
Ripples.shared.track("added transaction", userId: "user_123", properties: [
    "area": "transactions",
    "activated": true,
])
```

Force a flush (e.g. before logout):

```swift
Ripples.shared.flush { /* delivery attempted */ }
```

## How it works

* Every call enqueues a JSON event to `Application Support/ripples/<key>/queue`.
  The queue survives app restarts and being killed.
* A background timer flushes every `flushIntervalSeconds` (default 30s).
  Reaching `flushAt` events (default 20) triggers an immediate flush.
* `NWPathMonitor` pauses the queue while offline and kicks a flush the moment
  connectivity returns.
* `UIApplication.didEnterBackgroundNotification` and `willTerminateNotification`
  also trigger a flush so events aren't lost when the user backgrounds the app.
* `5xx`, `429`, and network errors back off exponentially (5s → 5m).
  Other `4xx` responses drop the batch — a malformed payload can't wedge the
  queue forever.

## Configuration

```swift
let config = RipplesConfig(apiKey: "priv_...")
config.host                 = "https://your-domain.com/api"   // self-hosted
config.flushIntervalSeconds = 30
config.flushAt              = 20
config.maxBatchSize         = 50
config.maxQueueSize         = 1000
config.requestTimeout       = 10
config.onError              = { error in /* log */ }
Ripples.setup(config)
```

## Requirements

* Swift 5.5+
* iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+

## License

MIT
