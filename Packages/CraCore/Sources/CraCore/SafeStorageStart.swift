import Foundation

/// Whether Chromium may open the profile, decided before it starts (SafeStorage in the app).
///
/// Chromium encrypts cookies, saved passwords and card numbers with the secret in the login
/// Keychain item "Cra Safe Storage". It deletes every cookie it cannot decrypt: the whole
/// eTLD+1 group goes from the Cookies database (net/extras/sqlite/sqlite_persistent_cookie_store.cc).
/// So once a profile uses the Keychain, Chromium starts only with that secret in hand. A denied
/// or cancelled Keychain prompt, a locked keychain, a missing item or an engine that looks for
/// another item would otherwise sign the user out of every site, and an app rollback would not
/// bring the logins back.
public enum SafeStorageStart: Equatable, Sendable {
    /// What the Keychain answered when Cra asked for the item.
    public enum Lookup: Equatable, Sendable {
        case found
        case missing
        /// Any other status: denied, cancelled, the keychain locked or unavailable.
        case failed(status: Int32)

        /// Security's errSecSuccess, errSecItemNotFound and errSecDecode (CraCore does not import Security).
        static let success: Int32 = 0
        static let itemNotFound: Int32 = -25300
        static let decode: Int32 = -26275

        /// From SecItemCopyMatching's status. `hasSecret`: the item's data decoded as text.
        public init(status: Int32, hasSecret: Bool) {
            switch status {
            case Self.success: self = hasSecret ? .found : .failed(status: Self.decode)
            case Self.itemNotFound: self = .missing
            default: self = .failed(status: status)
            }
        }
    }

    public enum Refusal: Equatable, Sendable {
        /// The Keychain did not hand out the secret. Asking again can work.
        case denied(status: Int32)
        /// The item is gone. Restoring the Keychain from a backup brings it back.
        case missing
        /// The framework looks for another Keychain item, so Chromium would make a new secret.
        case otherEngine
    }

    /// The framework binary as the file system knows it. A new copy, a download or an in-place
    /// patch (scripts/fetch-cef.sh writes with dd) changes at least one of these.
    public struct FrameworkFile: Codable, Equatable, Sendable {
        public let inode: UInt64
        public let size: Int64
        public let modifiedSeconds: Int64
        public let modifiedNanoseconds: Int64

        public init(inode: UInt64, size: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64) {
            self.inode = inode
            self.size = size
            self.modifiedSeconds = modifiedSeconds
            self.modifiedNanoseconds = modifiedNanoseconds
        }
    }

    case start
    case refuse(Refusal)

    /// Whether the framework must be read again to know that it uses "Cra Safe Storage". The
    /// read maps about 240 MB on the main thread before any window (about 50 ms warm, a page-in
    /// cold), so only a positive result is kept, for the exact file it came from. `current` is
    /// nil when the file could not be examined.
    public static func needsFrameworkScan(current: FrameworkFile?, verified: FrameworkFile?) -> Bool {
        guard let current else { return true }
        return current != verified
    }

    /// `profileUsesKeychain`: the profile was moved to the Keychain secret (SafeStorage's marker).
    /// The two checks are closures because both are costly: the lookup can show a Keychain
    /// prompt, and the framework check reads the framework. They run only when the answer matters.
    public static func decide(profileUsesKeychain: Bool, frameworkUsesCraItem: () -> Bool,
                              lookup: () -> Lookup) -> SafeStorageStart {
        guard profileUsesKeychain else { return .start }
        guard frameworkUsesCraItem() else { return .refuse(.otherEngine) }
        switch lookup() {
        case .found: return .start
        case .missing: return .refuse(.missing)
        case .failed(let status): return .refuse(.denied(status: status))
        }
    }
}
