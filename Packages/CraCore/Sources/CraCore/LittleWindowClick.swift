import Foundation

/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (Settings ▸ Links): a link clicked
/// with ⌥⌘ opens in a Little Window instead of a tab. Arc's release notes of 6 Oct 2022: "Command
/// Option Click now opens links in Little Arc!"; Arc 1.172.1 keeps it as a switch. Which clicks
/// those are: Chromium's "open in split view" (CEF_WOD_NEW_SPLIT_VIEW) on its pages,
/// LinkClick.Destination.littleWindow on WebKit's.
public enum LittleWindowClick {
    /// Whether such a click opens `url` in a Little Window. Little Windows load in the normal
    /// profile, so none from an incognito page, and they show pages only: cra: (Cra's scripting
    /// scheme), javascript: or another app's address keep the click's old path.
    public static func opens(_ url: String, incognito: Bool, settings: AppSettings) -> Bool {
        guard settings.littleWindowOnOptionCommandClick, !incognito,
              let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }
}
