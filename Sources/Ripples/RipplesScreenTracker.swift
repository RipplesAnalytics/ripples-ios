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
    /// When `name` is omitted the screen name is derived from the Swift type
    /// name with the `View` suffix stripped — `HomeView` → `"Home"`.
    ///
    ///     // Automatic name
    ///     List { ... }.trackScreen()
    ///
    ///     // Explicit name
    ///     List { ... }.trackScreen("Home")
    ///
    ///     // With extra properties
    ///     ScrollView { ... }.trackScreen(properties: ["list_id": listId])
    ///     ScrollView { ... }.trackScreen("ListDetail", properties: ["list_id": listId])
    ///
    /// - Parameters:
    ///   - name: Screen name shown in the Pages report. Defaults to the view's
    ///     type name with the `View` suffix removed.
    ///   - properties: Optional extra properties attached to the event.
    func trackScreen(_ name: String? = nil, properties: [String: Any] = [:]) -> some View {
        let resolved: String = name ?? {
            let typeName = String(describing: type(of: self))
            return typeName.hasSuffix("View") ? String(typeName.dropLast(4)) : typeName
        }()
        return modifier(ScreenTrackingModifier(screenName: resolved, properties: properties))
    }
}
#endif
