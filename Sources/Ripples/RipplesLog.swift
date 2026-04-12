import Foundation

func ripplesLog(_ message: @autoclosure () -> String) {
    if RipplesConfig.debugLogging {
        print("[Ripples] \(message())")
    }
}
