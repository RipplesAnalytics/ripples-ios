# Ripples iOS SDK

iOS / macOS / tvOS / watchOS client for [Ripples.sh](https://ripples.sh).

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/ripples-sh/ripples-ios", from: "0.1.6")
```

## Keys

Ripples projects have two identifiers:

| Key           | Format   | Where to use           | Scope                               |
|---------------|----------|------------------------|-------------------------------------|
| Secret key    | `priv_…` | Server-side only       | Full ingest access, incl. `revenue` |
| Project token | UUID     | iOS / web / any client | `track`, `identify`, `signup`, `pageview` only |

The iOS SDK takes the **project token**. It's safe to bundle: revenue events
from the token are rejected server-side, so a scraped key can't forge MRR / LTV.
Rotate in project settings if you see abuse.

**Never** ship the `priv_` key in a mobile or web app.

## Usage

Initialize once at app launch:

```swift
import Ripples

@main
struct MyApp: App {
    init() {
        Ripples.setup(RipplesConfig(projectToken: "YOUR-PROJECT-TOKEN"))
    }
}
```

### Identify a user

```swift
Ripples.shared.identify("user_123", traits: [
    "email": "jane@example.com",
    "name":  "Jane Smith",
])
```

### Track events

```swift
Ripples.shared.track("created a budget", userId: "user_123", properties: [
    "area": "budgets",
])

// Mark the activation moment
Ripples.shared.track("added transaction", userId: "user_123", properties: [
    "area":      "transactions",
    "activated": true,
])
```

### Track screen views

Use the SwiftUI modifier — one line per screen:

```swift
struct HomeView: View {
    var body: some View {
        List { ... }
            .trackScreen("Home")
    }
}

struct ProfileView: View {
    var body: some View {
        Form { ... }
            .trackScreen("Profile", userId: currentUserId)
    }
}
```

Or call it imperatively (e.g. UIKit or custom navigation):

```swift
Ripples.shared.screen("Settings", userId: "user_123")
```

Screen views are stored as `pageview` events and appear in the **Pages** report
alongside web pageviews. The first screen in each session is automatically
flagged as the session entry.

### Flush manually

```swift
// Before logout, account deletion, etc.
Ripples.shared.flush { /* delivery attempted */ }
```

## Automatic behaviour

| What                          | How                                                                 |
|-------------------------------|---------------------------------------------------------------------|
| **Persistent visitor ID**     | Generated once, stored to disk, survives reinstalls                 |
| **Session ID**                | New UUID on SDK init; rotates after 30 min in background            |
| **Device & OS metadata**      | Collected once at startup, merged into every event automatically    |
| **Geo / country**             | Resolved server-side from the request IP via Cloudflare headers     |
| **Offline queuing**           | Events persisted to disk; flushed when connectivity returns         |
| **Background flush**          | Queue flushed on `didEnterBackground` and `willTerminate`           |
| **Retry / backoff**           | 5xx / network errors back off exponentially (5s → 5 min)           |
| **Poison batch protection**   | Non-retryable 4xx drops the batch so a bad payload can't wedge the queue |

## Configuration

```swift
let config = RipplesConfig(projectToken: "YOUR-PROJECT-TOKEN")
config.host                 = "https://your-domain.com"  // self-hosted
config.flushIntervalSeconds = 30
config.flushAt              = 20
config.maxBatchSize         = 50
config.maxQueueSize         = 1000
config.requestTimeout       = 10
config.onError              = { error in print("Ripples error:", error) }
Ripples.setup(config)
```

## Requirements

* Swift 5.5+
* iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+

## License

MIT
