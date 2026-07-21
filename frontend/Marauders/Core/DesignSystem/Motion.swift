import SwiftUI

enum Motion {
    static let press = Animation.easeOut(duration: 0.12)
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.smooth(duration: 0.28)
    static let spring = Animation.spring(duration: 0.36, bounce: 0.12)
    static let reveal = Animation.easeOut(duration: 0.32)

    static func change(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : standard
    }

    static func subtleTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
}

private struct OneTimeStaggeredRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 8)
            .task {
                guard !isVisible else { return }
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(45 * min(max(index, 0), 6)))
                } catch {
                    return
                }
                withAnimation(Motion.reveal) { isVisible = true }
            }
    }
}

struct SubtlePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}

extension View {
    func oneTimeStaggeredReveal(_ index: Int) -> some View {
        modifier(OneTimeStaggeredRevealModifier(index: index))
    }
}
