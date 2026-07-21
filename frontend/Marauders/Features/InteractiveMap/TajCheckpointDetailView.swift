import SwiftUI

struct TajCheckpointDetailView: View {
    let chapterID: String
    let language: String
    @ObservedObject var progressStore: TajTourProgressStore
    @ObservedObject var insights: TajAIInsightStore
    @ObservedObject var narrator: AudioNarrationController
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    @ObservedObject var ambientPlayer: AmbientAudioPlayer
    let onOpenAR: () -> Void
    let onOpenBrowse: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showARUnavailable = false
    @State private var showGuideChat = false
    @State private var seekPosition = 0.0
    @State private var isSeeking = false

    private var chapter: TajMapCheckpoint? {
        progressStore.chapters.first { $0.id == chapterID }
    }

    var body: some View {
        let loaded = AnyView(navigationContent.task(id: "\(chapterID).\(language)") {
            if let chapter { await insights.load(for: chapter, language: language) }
        })
        let observed = AnyView(loaded.onChange(of: narrator.state) { oldState, newState in
            narrationStateChanged(oldState, newState)
        })
        let progressObserved = AnyView(observed.onChange(of: narrator.progress) { _, progress in
            if !isSeeking { seekPosition = progress }
        })
        let cleaned = AnyView(progressObserved.onDisappear(perform: stopNarration))
        return AnyView(cleaned.alert("AR preview unavailable", isPresented: $showARUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This chapter has no verified AR target yet. Its curated text and Audio Experience remain available offline.")
        })
    }

    private var navigationContent: some View {
        NavigationStack {
            ScrollView {
                chapterContent
            }
            .background(Theme.surfaceLow)
            .navigationTitle("Chapter \(chapter?.chapterNumber ?? 0)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        stopNarration()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chapterContent: some View {
        if let chapter {
            VStack(alignment: .leading, spacing: 20) {
                chapterHeader(chapter)
                informationCard(title: "Verified tour content", icon: "checkmark.seal.fill", text: chapter.verifiedInformation)
                aiInformation(chapter)
                audioExperience(chapter)
                detailGrid(chapter)
                actionButtons(chapter)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
    }

    private func narrationStateChanged(_: AudioNarrationController.State, _ state: AudioNarrationController.State) {
        ambientPlayer.setDucked(state == .speaking || state == .pausing, for: .checkpointSpeech)
    }

    private func stopNarration() {
        narrator.stop()
        ambientPlayer.setDucked(false, for: .checkpointSpeech)
    }

    private func chapterHeader(_ chapter: TajMapCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CHAPTER \(chapter.chapterNumber) OF 6", systemImage: chapter.status.icon)
                    .font(.caption.bold()).tracking(1)
                    .foregroundStyle(chapter.status.color)
                Spacer()
                Text(chapter.status.label)
                    .textCase(.uppercase)
                    .font(.caption2.bold()).tracking(0.8)
                    .foregroundStyle(chapter.status.color)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(chapter.status.color.opacity(0.12), in: Capsule())
            }
            Text(verbatim: chapter.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("A location-specific chapter in your Taj Mahal route.")
                .foregroundStyle(Theme.mutedInk)
        }
        .padding(18)
        .heritageCard()
    }

    private func informationCard(title: LocalizedStringKey, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(Theme.primary)
            Text(verbatim: text).foregroundStyle(Theme.mutedInk).lineSpacing(4)
        }
        .padding(18)
        .heritageCard()
    }

    @ViewBuilder
    private func aiInformation(_ chapter: TajMapCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Guide insight", systemImage: "book.closed.fill").font(.headline).foregroundStyle(Theme.primary)
            }
            switch insights.state(for: chapter.id, language: language) {
            case .idle, .loading:
                HStack { ProgressView(); Text("Preparing guide insight…") }.foregroundStyle(Theme.mutedInk)
            case .success(let text):
                Text(verbatim: text).foregroundStyle(Theme.mutedInk).lineSpacing(4)
                Text("Insights may be generated remotely and cached on this device. When that is unavailable, the bundled chapter summary is used.")
                    .font(.caption).foregroundStyle(Theme.mutedInk.opacity(0.8))
            case .failure:
                Label("Guide insight is unavailable right now.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.primary)
                Button("Retry") { Task { await insights.retry(for: chapter, language: language) } }
                    .buttonStyle(.bordered)
            }
            Button {
                stopCompetingAudio()
                showGuideChat = true
            } label: {
                Label("Ask the guide a question", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .accessibilityIdentifier("askGuideButton")
        }
        .padding(18)
        .heritageCard()
        .sheet(isPresented: $showGuideChat) {
            AIGuideView(context: AIGuideContext(
                monumentID: "taj_mahal",
                monumentName: "Taj Mahal",
                checkpointID: TajAIInsightStore.backendCheckpointID(forChapter: chapter.id),
                checkpointName: chapter.name,
                language: language
            ))
            .onAppear(perform: stopCompetingAudio)
        }
    }

    private func stopCompetingAudio() {
        stopNarration()
        audioPlayer.stop()
    }

    private func detailGrid(_ chapter: TajMapCheckpoint) -> some View {
        VStack(spacing: 12) {
            detailRow("Architecture", "building.columns.fill", chapter.architecture)
            detailRow("Historical context", "clock.fill", chapter.historicalContext)
            detailRow("Interesting fact", "lightbulb.fill", chapter.interestingFact)
            detailRow("Visitor guidance", "figure.walk", chapter.visitorGuidance)
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).foregroundStyle(Theme.gold).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.ink)
                Text(verbatim: text).font(.subheadline).foregroundStyle(Theme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func audioExperience(_ chapter: TajMapCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Experience", systemImage: "waveform.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(Theme.primary)
                Spacer()
                speedButton("0.8x", accessibilityLabel: "0.8x playback speed", multiplier: 0.8)
                speedButton("1.2x", accessibilityLabel: "1.2x playback speed", multiplier: 1.2)
            }
            Slider(
                value: Binding(
                    get: { isSeeking ? seekPosition : narrator.progress },
                    set: { seekPosition = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { narrator.seek(to: seekPosition) }
                }
            )
            .tint(Theme.gold)
            .disabled(narrator.state == .idle)
            .accessibilityLabel("Narration position")
            .accessibilityValue("\(Int((isSeeking ? seekPosition : narrator.progress) * 100)) percent")
            HStack {
                Text(verbatim: time(isSeeking ? narrator.estimatedDuration * seekPosition : narrator.elapsed))
                Spacer()
                Text(verbatim: time(narrator.estimatedDuration))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(Theme.mutedInk)
            HStack(spacing: 8) {
                Button { narrator.restart() } label: {
                    transportLabel("Replay", icon: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                .disabled(narrator.estimatedDuration == 0)

                Button {
                    if narrator.isSpeaking {
                        narrator.pause()
                    } else {
                        play(chapter)
                    }
                } label: {
                    transportLabel(
                        narrator.isSpeaking ? "Pause" : "Play",
                        icon: narrator.isSpeaking ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .accessibilityLabel(narrator.isSpeaking ? "Pause narration" : narrator.state == .paused ? "Resume narration" : "Play narration")

                Button { narrator.stop() } label: {
                    transportLabel("Stop", icon: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                .disabled(narrator.state == .idle)
            }
        }
        .padding(14)
        .heritageCard()
    }

    private func speedButton(
        _ title: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey,
        multiplier: Float
    ) -> some View {
        Button { narrator.setPlaybackSpeed(multiplier) } label: {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(abs(narrator.playbackSpeed - multiplier) < 0.05 ? Theme.primary : Theme.mutedInk)
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                .background(Theme.surfaceContainer, in: Capsule())
        }
        .buttonStyle(SubtlePressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func transportLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func actionButtons(_ chapter: TajMapCheckpoint) -> some View {
        actionLayout {
            Button {
                narrator.stop()
                onOpenBrowse()
            } label: {
                compactActionLabel("Local Stories", icon: "headphones")
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .accessibilityLabel("Browse Local Stories")
            .accessibilityIdentifier("tajBrowseStoriesButton")

            Button {
                narrator.stop()
                if chapter.arAssetName == nil { showARUnavailable = true } else { onOpenAR() }
            } label: {
                compactActionLabel("AR", icon: "arkit")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .accessibilityLabel("AR Experience")

            Button {
                let completion = { _ = progressStore.completeSelectedChapter() }
                if reduceMotion { completion() } else { withAnimation(.easeInOut(duration: 0.3), completion) }
            } label: {
                compactActionLabel(
                    chapter.status == .completed ? "Completed" : "Complete",
                    icon: chapter.status == .completed ? "checkmark.seal.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.teal)
            .disabled(!progressStore.canCompleteSelectedChapter)
            .accessibilityLabel(chapter.status == .completed ? "Chapter Completed" : "Complete Chapter")
            .accessibilityIdentifier("tajCompleteChapterButton")
        }
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private func compactActionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(title).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func play(_ chapter: TajMapCheckpoint) {
        audioPlayer.stop()
        if narrator.state == .paused {
            narrator.resume()
            return
        }
        let insight: String
        if case .success(let value) = insights.state(for: chapter.id, language: language) { insight = value } else { insight = chapter.fallbackAIInformation }
        let text = [chapter.verifiedInformation, insight, chapter.architecture, chapter.historicalContext, chapter.interestingFact, chapter.visitorGuidance]
            .filter { !$0.isEmpty }.joined(separator: " ")
        narrator.play(text: text, languageCode: "en", chapterID: chapter.id)
    }

    private func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let seconds = max(Int(interval), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

extension CheckpointStatus {
    var color: Color {
        switch self {
        case .completed: Theme.teal
        case .active: Theme.primary
        case .available: Theme.gold
        case .upcoming: Theme.gold.opacity(0.65)
        case .locked: Theme.mutedInk
        }
    }

    var icon: String {
        switch self {
        case .completed: "checkmark"
        case .active: "location.fill"
        case .available: "circle.fill"
        case .upcoming: "clock.fill"
        case .locked: "lock.fill"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .completed: "Completed"
        case .active: "Current"
        case .available: "Available"
        case .upcoming: "Upcoming"
        case .locked: "Locked"
        }
    }
}
