import SwiftUI
import UIKit

struct AIGuideView: View {
    let context: AIGuideContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var chat = AIGuideChatService()
    @State private var draft = ""
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        guideHeader
                        ForEach(chat.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if chat.isLoading { thinkingBubble.id("thinking") }
                        if let error = chat.errorMessage { errorBubble(error).id("error") }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.surfaceLow)
                .onChange(of: chat.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: chat.isLoading) { _, isLoading in
                    scrollToBottom(proxy)
                    if isLoading { announce(String(localized: "AI Guide is thinking")) }
                }
                .onChange(of: chat.messages.last) { _, message in
                    guard let message, message.role == .guide else { return }
                    announce(String(localized: "AI Guide replied. \(message.text)"))
                }
                .onChange(of: chat.errorMessage) { _, error in
                    if let error { announce(String(localized: "AI Guide error. \(error)")) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("AI Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        cancelRequest()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { cancelRequest() }
    }

    private var guideHeader: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Theme.goldLight.opacity(0.35), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Ask about \(context.monumentName)")
                    .font(.headline).foregroundStyle(Theme.ink)
                Text("Your question will use the guide content for \(context.checkpointName).")
                    .font(.subheadline).foregroundStyle(Theme.mutedInk)
                Text("AI responses may contain mistakes. Check important details with venue staff.")
                    .font(.caption).foregroundStyle(Theme.mutedInk.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .heritageCard()
    }

    private func messageBubble(_ message: AIGuideChatService.Message) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            Text(verbatim: message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    message.role == .user ? Theme.primary : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    if message.role == .guide {
                        RoundedRectangle(cornerRadius: 18).stroke(Theme.outline.opacity(0.55))
                    }
                }
            if message.role == .guide { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(messageAccessibilityLabel(message))
    }

    private var thinkingBubble: some View {
        HStack(spacing: 9) {
            ProgressView().tint(Theme.primary)
            Text("Looking through the local guide…")
                .font(.subheadline).foregroundStyle(Theme.mutedInk)
            Spacer()
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Guide is looking through the local guide")
    }

    private func errorBubble(_ error: String) -> some View {
        Label {
            Text(verbatim: error)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
            .font(.subheadline).foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask your guide…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.surfaceContainer, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("aiGuideComposer")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Theme.primary : Theme.mutedInk.opacity(0.35), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send question")
            .accessibilityIdentifier("aiGuideSendButton")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func send() {
        guard canSend else { return }
        let question = draft
        draft = ""
        requestTask?.cancel()
        requestTask = Task { await chat.send(question, context: context) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let scroll = {
            if chat.isLoading {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if chat.errorMessage != nil {
                proxy.scrollTo("error", anchor: .bottom)
            } else if let message = chat.messages.last {
                proxy.scrollTo(message.id, anchor: .bottom)
            }
        }
        if reduceMotion {
            scroll()
        } else {
            withAnimation(Motion.quick, scroll)
        }
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        chat.cancel()
    }

    private func messageAccessibilityLabel(_ message: AIGuideChatService.Message) -> Text {
        if message.role == .user {
            Text("You: \(Text(verbatim: message.text))")
        } else {
            Text("AI Guide: \(Text(verbatim: message.text))")
        }
    }

    private func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
