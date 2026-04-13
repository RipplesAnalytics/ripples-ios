import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// Fires a screen-view event when the view appears and deduplicates rapid
/// re-appearances (e.g. SwiftUI calling onAppear twice during navigation).
private struct ScreenTrackingModifier: ViewModifier {

    let screenName: String
    let properties: [String: Any]

    /// Ignore re-appearances within this window to avoid double-fires from
    /// SwiftUI's eager onAppear during tab/navigation transitions.
    private static let dedupeInterval: TimeInterval = 1.0

    @State private var lastFired: Date = .distantPast

    func body(content: Content) -> some View {
        content.onAppear {
            let now = Date()
            guard now.timeIntervalSince(lastFired) > Self.dedupeInterval else { return }
            lastFired = now
            Ripples.shared.screen(screenName, properties: properties)
        }
    }
}

public extension View {
    /// Track this view as a screen visit in Ripples.
    ///
    ///     struct HomeView: View {
    ///         var body: some View {
    ///             List { ... }
    ///                 .trackScreen("Home")
    ///         }
    ///     }
    ///
    ///     struct ListDetailView: View {
    ///         let listId: String
    ///         var body: some View {
    ///             ScrollView { ... }
    ///                 .trackScreen("ListDetail", properties: ["list_id": listId])
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - name: Screen name shown in the Pages report.
    ///   - properties: Optional extra properties attached to the event.
    func trackScreen(_ name: String, properties: [String: Any] = [:]) -> some View {
        modifier(ScreenTrackingModifier(screenName: name, properties: properties))
    }
}
#endif
