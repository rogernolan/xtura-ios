import Foundation

struct TabBarVisibilityModel {
    enum Orientation {
        case portrait
        case landscape
    }

    private(set) var isTabBarVisible = true

    mutating func update(for orientation: Orientation) {
        isTabBarVisible = orientation == .portrait
    }
}
