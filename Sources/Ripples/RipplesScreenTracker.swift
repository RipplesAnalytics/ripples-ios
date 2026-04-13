import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// Fires a screen-view event when the view appears and deduplicates rapid
/// re-appearances (e.g. SwiftUI calling onAppear twice during navigation).
private struct ScreenTrackingModifier: ViewModifier {

    let screenName: String
    let userId: String

    /// Ignore re-appearances within this window to avoid double-fires from
    /// SwiftUI's eager onAppear during tab/navigation transitions.
    private static let dedupeInterval: TimeInterval = 1.0

    @State private var lastFired: Date = .distantPast

    func body(content: Content) -> some View {
        content.onAppear {
            let now = Date()
            guard now.timeIntervalSince(lastFired) > Self.dedupeInterval else { return }
            lastFired = now
            Ripples.shared.screen(screenName, userId: userId)
        }
    }
}

public extension View {
    /// Track this view as a screen visit in Ripples.
    ///
    /// Place it on your top-level screen view, not on individual components:
    ///
    ///     struct HomeView: View {
    ///         var body: some View {
    ///             List { ... }
    ///                 .trackScreen("Home")
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - name: Human-readable screen name shown in the Pages report.
    ///   - userId: Optional. Pass the authenticated user's ID if known.
    func trackScreen(_ name: String, userId: String = "") -> some View {
        modifier(ScreenTrackingModifier(screenName: name, userId: userId))
    }
}
#endif
