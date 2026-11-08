import CraCore
import Testing

/// A test copy of Cra that runs behind the user's apps never comes to the front; the user's Cra
/// (no CRA_TEST_BACKGROUND) does, as before.
struct TestInstanceTests {
    @Test(arguments: [
        ([:], false),
        (["CRA_TEST_BACKGROUND": "1"], true),
        (["CRA_TEST_BACKGROUND": "0"], false),
        (["CRA_TEST_BACKGROUND": ""], false),
        (["CRA_TEST_BACKGROUND": "true"], false),
        (["CRA_HITCH_LOG": "/tmp/hitch.log"], false),
    ] as [([String: String], Bool)])
    func whichCopiesStayBehind(environment: [String: String], background: Bool) {
        let copy = TestInstance(environment: environment)
        #expect(copy.background == background)
        #expect(copy.activates == !background)
    }
}
