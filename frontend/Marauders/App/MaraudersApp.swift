import SwiftUI
import SwiftData
import TipKit

@main
struct MaraudersApp: App {
    @State private var session = AppSession()

    init() {
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.light)
                .modelContainer(for: VisitedNugget.self)
        }
    }
}
