import Foundation

/// Always prints — use for errors and warnings.
func ripplesLog(_ message: @autoclosure () -> String) {
    print("[Ripples] \(message())")
}

/// Only prints when `RipplesConfig.debugLogging` is enabled — use for verbose/informational output.
func ripplesDebug(_ message: @autoclosure () -> String) {
    if RipplesConfig.debugLogging {
        print("[Ripples] \(message())")
    }
}
