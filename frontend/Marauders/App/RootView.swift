import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if session.isAuthenticated {
                MainTabView()
                    .transition(Motion.subtleTransition(reduceMotion: reduceMotion))
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.change(reduceMotion: reduceMotion), value: session.isAuthenticated)
        .environment(\.locale, Locale(identifier: session.appLanguage.localeIdentifier))
        .contrast(session.prefersHighContrast ? 1.18 : 1)
        .modifier(PreferredTextSizeModifier(enabled: session.prefersLargeText))
    }
}

private struct PreferredTextSizeModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, !dynamicTypeSize.isAccessibilitySize {
            content.dynamicTypeSize(.accessibility1)
        } else {
            content
        }
    }
}
