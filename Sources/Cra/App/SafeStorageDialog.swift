import AppKit

/// Shown before Chromium starts when SafeStorageStart refuses the profile, because Chromium
/// would delete every cookie it cannot decrypt. Quit leaves the profile as it is.
enum SafeStorageDialog {
    /// true: ask the Keychain again. false: quit.
    @MainActor static func tryAgain(after refusal: SafeStorageStart.Refusal) -> Bool {
        let message: String
        var actions = [DialogAction("Try Again"), DialogAction("Quit", role: .cancel)]
        switch refusal {
        case .denied:
            message = "macOS didn't give Cra access to “Cra Safe Storage” in your Keychain. "
                + "Click Try Again, then choose Always Allow."
        case .missing:
            message = "Your Keychain has no “Cra Safe Storage” item, which unlocks your cookies and saved passwords. "
                + "Restore it from a backup of your Keychain, then try again."
        case .otherEngine:
            message = "This copy of Cra's engine doesn't use “Cra Safe Storage”, so it can't read your saved logins. "
                + "Install Cra again."
            actions = [DialogAction("Quit")]
        }
        let dialog = AppDialog(title: "Cra can't unlock your saved logins", message: message, actions: actions)
        // As NewestCopy's dialog: the launch may not be active yet, so it floats and stays visible.
        let window = dialog.prepareWindow()
        window.hidesOnDeactivate = false
        RunLoop.current.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                window.level = .floating
                window.orderFrontRegardless()
            }
        }
        NSApp.activate()
        let response = dialog.runModal(over: nil)
        return refusal != .otherEngine && response == .alertFirstButtonReturn
    }
}
