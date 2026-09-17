import SwiftUI
import UIKit

/// Keeps the screen awake while narration is running.
///
/// A match lasts ninety minutes and the listener may not touch the phone once in that time. Letting
/// the display sleep is not merely inconvenient: on lock, the app loses the foreground, polling and
/// speech are cut, and someone following by ear has no way to tell that from the match having gone
/// quiet.
///
/// Scoped to narration on purpose. Holding the screen awake for the whole session would drain the
/// battery of a listener who opened the app to check the next fixture, and battery is not a
/// detail across ninety minutes of audio.
///
/// The flag is released when narration stops and when the app leaves the foreground, so it is never
/// left set by a screen that went away.
struct KeepsScreenAwake: ViewModifier {
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                apply(active)
            }
            .onChange(of: scenePhase) { _, phase in
                // Backgrounded apps do not control the idle timer, and leaving it set would be a
                // promise the app cannot keep.
                apply(phase == .active && isActive)
            }
            .onDisappear { apply(false) }
    }

    private func apply(_ keepAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }
}

extension View {
    /// Prevents the display from sleeping while `isActive` is true.
    func keepsScreenAwake(_ isActive: Bool) -> some View {
        modifier(KeepsScreenAwake(isActive: isActive))
    }
}
