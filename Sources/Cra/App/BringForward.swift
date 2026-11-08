import AppKit

/// Every "bring Cra to the front" goes through here, so a copy the tests run behind the user's
/// apps (`TestInstance.background`) never takes focus from them. In the user's Cra both are
/// exactly NSApplication's own calls. `scripts/lint.py` (`activate-outside-helper`) keeps
/// NSApp.activate out of every other file.
extension NSApplication {
    /// `activate(ignoringOtherApps:)`, except in a background test copy.
    func bringCraForward(ignoringOtherApps: Bool) {
        guard HitchMonitor.testInstance.activates else { return }
        activate(ignoringOtherApps: ignoringOtherApps)
    }

    /// `activate()`, the cooperative activation, except in a background test copy.
    func bringCraForward() {
        guard HitchMonitor.testInstance.activates else { return }
        activate()
    }
}
