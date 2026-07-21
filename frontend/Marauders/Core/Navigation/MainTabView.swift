import SwiftUI

struct MainTabView: View {
    @StateObject private var packageCatalog = PackageCatalog()

    var body: some View {
        TabView {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "ticket.fill") }

            BookingsView()
                .tabItem { Label("My Tours", systemImage: "map.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .environmentObject(packageCatalog)
        .task { await packageCatalog.refresh() }
        .tint(Theme.primary)
    }
}
