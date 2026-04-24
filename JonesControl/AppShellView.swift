import SwiftUI

struct AppShellView: View {
    enum Tab: Hashable {
        case garmin
        case heating
        case settings
    }

    @State private var selectedTab: Tab = .garmin
    @State private var tabBarVisibilityModel = TabBarVisibilityModel()
    @State private var heatingServiceSettings = HeatingServiceSettings()

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedTab) {
                GarminView()
                    .tabItem {
                        Label("Garmin", systemImage: "globe")
                    }
                    .tag(Tab.garmin)

                HeatingView()
                    .tabItem {
                        Label("Heating", systemImage: "flame")
                    }
                    .tag(Tab.heating)

                SettingsView(settings: heatingServiceSettings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(Tab.settings)
            }
            .environment(heatingServiceSettings)
            .onAppear {
                updateTabBarVisibility(for: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateTabBarVisibility(for: newSize)
            }
            .toolbar(tabBarVisibilityModel.isTabBarVisible ? .visible : .hidden, for: .tabBar)
        }
    }

    private func updateTabBarVisibility(for size: CGSize) {
        let orientation = Self.orientation(for: size)
        withAnimation(.easeInOut(duration: 0.25)) {
            tabBarVisibilityModel.update(for: orientation)
        }
    }

    private static func orientation(for size: CGSize) -> TabBarVisibilityModel.Orientation {
        size.width > size.height ? .landscape : .portrait
    }
}
