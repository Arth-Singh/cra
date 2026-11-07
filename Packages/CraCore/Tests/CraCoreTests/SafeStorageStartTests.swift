import CraCore
import Testing

/// Chromium opens a Keychain profile only with the "Cra Safe Storage" secret in hand: without
/// it, it deletes every cookie it cannot decrypt and the user is signed out of every site.
struct SafeStorageStartTests {
    /// errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecNoSuchKeychain.
    static let failures: [Int32] = [-128, -25293, -25308, -25294]

    /// A profile that never used the Keychain (an unsigned dev build) keeps the mock keychain,
    /// and Cra neither reads the framework nor asks the Keychain for it.
    @Test func mockKeychainProfileStartsWithoutAsking() {
        var asked: [String] = []
        let decision = SafeStorageStart.decide(profileUsesKeychain: false,
                                               frameworkUsesCraItem: { asked.append("framework"); return false },
                                               lookup: { asked.append("keychain"); return .failed(status: -128) })
        #expect(decision == .start)
        #expect(asked.isEmpty)
    }

    @Test func keychainProfileStartsWithTheSecret() {
        #expect(SafeStorageStart.decide(profileUsesKeychain: true, frameworkUsesCraItem: { true }, lookup: { .found }) == .start)
    }

    /// Deny or Cancel on the Keychain prompt, or a locked keychain: Chromium does not start.
    @Test(arguments: failures)
    func keychainProfileWithoutTheSecretDoesNotStart(status: Int32) {
        let decision = SafeStorageStart.decide(profileUsesKeychain: true, frameworkUsesCraItem: { true },
                                               lookup: { .failed(status: status) })
        #expect(decision == .refuse(.denied(status: status)))
    }

    /// A missing item is not made again: a new secret cannot decrypt the old cookies either.
    @Test func keychainProfileWithTheItemGoneDoesNotStart() {
        let decision = SafeStorageStart.decide(profileUsesKeychain: true, frameworkUsesCraItem: { true }, lookup: { .missing })
        #expect(decision == .refuse(.missing))
    }

    /// Only errSecItemNotFound means the item is gone; every other failure can pass with a retry.
    @Test(arguments: [
        (Int32(0), true, SafeStorageStart.Lookup.found),
        (0, false, .failed(status: -26275)),  // an item whose data is no text secret
        (-25300, false, .missing),
        (-128, false, .failed(status: -128)),  // Deny or Cancel
        (-25308, false, .failed(status: -25308)),  // no UI: the keychain is locked
    ])
    func keychainStatuses(status: Int32, hasSecret: Bool, lookup: SafeStorageStart.Lookup) {
        #expect(SafeStorageStart.Lookup(status: status, hasSecret: hasSecret) == lookup)
    }

    static let framework = SafeStorageStart.FrameworkFile(inode: 4_211_993, size: 238_000_000,
                                                          modifiedSeconds: 1_793_210_039, modifiedNanoseconds: 120)

    /// The file that was found to use the Cra item is not read again at the next launch.
    @Test func verifiedFrameworkIsNotReadAgain() {
        #expect(!SafeStorageStart.needsFrameworkScan(current: Self.framework, verified: Self.framework))
    }

    /// Any other file, or one that can't be examined, is read: a positive result only holds for its file.
    @Test(arguments: [
        SafeStorageStart.FrameworkFile(inode: 4_211_994, size: 238_000_000, modifiedSeconds: 1_793_210_039, modifiedNanoseconds: 120),
        SafeStorageStart.FrameworkFile(inode: 4_211_993, size: 238_000_001, modifiedSeconds: 1_793_210_039, modifiedNanoseconds: 120),
        SafeStorageStart.FrameworkFile(inode: 4_211_993, size: 238_000_000, modifiedSeconds: 1_793_210_040, modifiedNanoseconds: 120),
        SafeStorageStart.FrameworkFile(inode: 4_211_993, size: 238_000_000, modifiedSeconds: 1_793_210_039, modifiedNanoseconds: 121),
    ])
    func anotherFrameworkFileIsRead(current: SafeStorageStart.FrameworkFile) {
        #expect(SafeStorageStart.needsFrameworkScan(current: current, verified: Self.framework))
    }

    @Test func unknownFrameworkFileIsRead() {
        #expect(SafeStorageStart.needsFrameworkScan(current: nil, verified: Self.framework))
        #expect(SafeStorageStart.needsFrameworkScan(current: nil, verified: nil))
        #expect(SafeStorageStart.needsFrameworkScan(current: Self.framework, verified: nil))
    }

    /// An engine that looks for "Chromium Safe Storage" would make its own secret. Cra refuses
    /// before it asks the Keychain, so there is no prompt for a launch that cannot go on.
    @Test func engineWithAnotherItemDoesNotStartOrAsk() {
        var asked = false
        let decision = SafeStorageStart.decide(profileUsesKeychain: true, frameworkUsesCraItem: { false },
                                               lookup: { asked = true; return .found })
        #expect(decision == .refuse(.otherEngine))
        #expect(!asked)
    }
}
