/// A copy of Cra that the tests started, read from its environment.
public struct TestInstance: Equatable, Sendable {
    /// CRA_TEST_BACKGROUND=1 (scripts/scenario.sh, Tests/smoke-launch.sh): it runs behind the
    /// user's apps, on their own Mac too, and is measured there.
    public let background: Bool

    public init(environment: [String: String]) {
        background = environment["CRA_TEST_BACKGROUND"] == "1"
    }

    /// Whether bringing Cra to the front activates the app: always for the user's Cra. A
    /// background copy never does, or a click, a key press or ⌘Q meant for the user's own
    /// Cra lands in it.
    public var activates: Bool { !background }
}
