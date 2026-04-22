import Testing
@testable import JonesControl

struct TabBarVisibilityModelTests {
    @Test func portraitKeepsTabBarVisible() {
        var model = TabBarVisibilityModel()

        model.update(for: .portrait)

        #expect(model.isTabBarVisible)
    }

    @Test func landscapeHidesTabBar() {
        var model = TabBarVisibilityModel()

        model.update(for: .landscape)

        #expect(model.isTabBarVisible == false)
    }
}
