import SwiftUI

struct BrowseModeView: View {
    @ObservedObject var session: TourSession
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    let onEngage: (Checkpoint, Nugget) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedNugget: Nugget?

    var body: some View {
        ZStack {
            Theme.surfaceLow.ignoresSafeArea()
            if let nugget = revealedNugget {
                NuggetRevealCard(
                    session: session,
                    nugget: nugget,
                    audioPlayer: audioPlayer,
                    onReplay: { replay(nugget) },
                    onClose: { withAnimation(Motion.change(reduceMotion: reduceMotion)) { revealedNugget = nil } }
                )
                .transition(Motion.subtleTransition(reduceMotion: reduceMotion))
            } else {
                list
            }
        }
    }

    private var list: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    checkpointPicker
                    if let checkpoint = session.currentCheckpoint {
                        Text(checkpoint.intro.v(session.language)).foregroundStyle(Theme.mutedInk)
                        ForEach(checkpoint.nuggets) { nugget in nuggetCard(checkpoint: checkpoint, nugget: nugget) }
                    }
                }
                .padding(20)
                .animation(Motion.change(reduceMotion: reduceMotion), value: session.currentCheckpointID)
            }
            .background(Theme.surfaceLow)
            .navigationTitle("Audio Experience")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var checkpointPicker: some View {
        Picker("Checkpoint", selection: $session.currentCheckpointID) {
            ForEach(session.installed.package.checkpoints.sorted { $0.order < $1.order }) { checkpoint in
                Text("\(checkpoint.order + 1). \(checkpoint.name.v(session.language))").tag(checkpoint.id)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.primary)
    }

    private func nuggetCard(checkpoint: Checkpoint, nugget: Nugget) -> some View {
        Button {
            onEngage(checkpoint, nugget)
            withAnimation(Motion.change(reduceMotion: reduceMotion)) { revealedNugget = nugget }
        } label: {
            HStack(spacing: 14) {
                NuggetMediaView(url: session.installed.displayURLs(for: nugget).first ?? session.installed.targetURL(for: nugget))
                    .frame(width: 88, height: 88).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 7) {
                    if nugget.exclusive { Text("★ EXCLUSIVE").font(.caption2.bold()).tracking(0.8).foregroundStyle(Theme.gold) }
                    Text(nugget.title.v(session.language)).font(.headline).foregroundStyle(Theme.ink)
                    Text(nugget.text.v(session.language)).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(2)
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.primary)
            }
            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(Theme.outline.opacity(0.55)) }
        }
        .accessibilityIdentifier("browseNugget_\(nugget.id)")
    }

    private func replay(_ nugget: Nugget) {
        guard let checkpoint = session.checkpoint(containing: nugget.id) else { return }
        onEngage(checkpoint, nugget)
    }
}
