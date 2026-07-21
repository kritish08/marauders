import SwiftUI

struct NuggetRevealCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: TourSession
    let nugget: Nugget
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    let onReplay: () -> Void
    let onClose: () -> Void
    @State private var sweepOffset: CGFloat = -1.2
    @State private var seekPosition = 0.0
    @State private var isSeeking = false

    private var isCurrentAudio: Bool { audioPlayer.isCurrent(nuggetID: nugget.id) }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    if nugget.exclusive {
                        Label("GUIDE-EXCLUSIVE SECRET", systemImage: "star.fill")
                            .font(.caption.bold()).tracking(1).foregroundStyle(Theme.gold)
                    }
                    Text(nugget.title.v(session.language))
                        .font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("nuggetRevealTitle_\(nugget.id)")
                    Text(nugget.text.v(session.language))
                        .font(.body).foregroundStyle(Theme.mutedInk).lineSpacing(5)
                    audioControls
                }
                .padding(20).padding(.bottom, 110)
            }
            closeButton
        }
        .onChange(of: audioPlayer.progress) { _, progress in
            if !isSeeking { seekPosition = progress }
        }
        .onDisappear {
            stopOwnedAudio()
        }
    }

    private var hero: some View {
        NuggetGallery(urls: session.installed.displayURLs(for: nugget), nuggetID: nugget.id)
            .frame(height: 310).clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, Theme.goldLight.opacity(0.72), .white.opacity(0.8), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .rotationEffect(.degrees(-12))
                    .offset(x: reduceMotion ? 0 : sweepOffset * 420)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(Theme.gold.opacity(0.35), lineWidth: 1) }
            .shadow(color: Theme.gold.opacity(0.2), radius: 20, y: 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).delay(0.15)) { sweepOffset = 1.2 }
            }
    }

    private var closeButton: some View {
        Button {
            stopOwnedAudio()
            onClose()
        } label: {
            Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(28)
        .accessibilityIdentifier("closeNuggetReveal")
    }

    private func stopOwnedAudio() {
        guard audioPlayer.isCurrent(nuggetID: nugget.id) else { return }
        audioPlayer.stop()
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Audio Experience", systemImage: "waveform.circle.fill")
                .font(.subheadline.bold()).foregroundStyle(Theme.primary)
            Slider(
                value: Binding(
                    get: { isSeeking ? seekPosition : audioPlayer.progress },
                    set: { seekPosition = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { audioPlayer.seek(to: seekPosition) }
                }
            )
            .tint(Theme.gold)
            .disabled(!isCurrentAudio)
            .accessibilityLabel("Story audio position")
            .accessibilityValue("\(Int((isSeeking ? seekPosition : audioPlayer.progress) * 100)) percent")
            HStack {
                Text(time(isSeeking ? audioPlayer.duration * seekPosition : audioPlayer.elapsed))
                Spacer()
                Text(time(audioPlayer.duration))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(Theme.mutedInk)
            audioActionLayout {
                Button(action: onReplay) {
                    audioButtonLabel("Replay", icon: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)

                Button {
                    if isCurrentAudio { audioPlayer.toggle() } else { onReplay() }
                } label: {
                    audioButtonLabel(
                        isCurrentAudio && audioPlayer.isPlaying ? "Pause" : "Play",
                        icon: isCurrentAudio && audioPlayer.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)

                Button { audioPlayer.stop() } label: {
                    audioButtonLabel("Stop", icon: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                .disabled(!isCurrentAudio)
            }
        }
        .padding(14)
        .heritageCard()
    }

    private var audioActionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private func audioButtonLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.bold()).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let seconds = max(Int(interval), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct NuggetGallery: View {
    let urls: [URL]
    let nuggetID: String

    var body: some View {
        TabView {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                NuggetMediaView(url: url)
                    .accessibilityLabel("Image \(index + 1) of \(urls.count)")
                    .accessibilityIdentifier("nuggetGalleryPage_\(nuggetID)_\(index)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
        .accessibilityIdentifier("nuggetGallery_\(nuggetID)")
    }
}

struct NuggetMediaView: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.surfaceContainer
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42)).foregroundStyle(Theme.outline)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
