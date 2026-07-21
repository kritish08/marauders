import SwiftUI

struct MonumentInfoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: TourSession
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    let visitedNuggetIDs: Set<String>
    let onSelectCheckpoint: (Checkpoint) -> Void
    @State private var selectedCheckpoint: Checkpoint?

    private var orderedCheckpoints: [Checkpoint] {
        session.installed.package.checkpoints.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.oneTimeStaggeredReveal(0)
                Group {
                    if let nugget = session.activeNugget { activeNugget(nugget) } else { emptyState }
                }
                .transition(Motion.subtleTransition(reduceMotion: reduceMotion))
                .animation(Motion.change(reduceMotion: reduceMotion), value: session.activeNugget?.id)
                .oneTimeStaggeredReveal(1)
                checkpointList.oneTimeStaggeredReveal(2)
            }.padding(20).padding(.bottom, 105)
        }
        .background(Theme.surfaceLow)
        .sheet(item: $selectedCheckpoint) { checkpoint in
            CheckpointGuideSheet(checkpoint: checkpoint, language: session.language)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.installed.package.monument.name.v(session.language)).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
            Text(session.installed.package.monument.overview.v(session.language)).foregroundStyle(Theme.mutedInk)
            Label("\(visitedNuggetIDs.count) of \(session.installed.package.checkpoints.flatMap(\.nuggets).count) secrets found", systemImage: "sparkles")
                .font(.subheadline.bold()).foregroundStyle(Theme.teal)
        }
    }

    private func activeNugget(_ nugget: Nugget) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if nugget.exclusive { Text("★ GUIDE-EXCLUSIVE SECRET").font(.caption.bold()).tracking(1).foregroundStyle(Theme.gold) }
            Text(nugget.title.v(session.language)).font(.title2.bold())
            Text(nugget.text.v(session.language)).foregroundStyle(Theme.mutedInk)
            Button {
                audioPlayer.replay(nugget: nugget, language: session.language, directory: session.installed.directory)
            } label: { Label("Replay local audio", systemImage: "play.circle.fill") }
            .buttonStyle(PrimaryButtonStyle())
        }.padding(18).heritageCard()
    }

    private var emptyState: some View {
        ContentUnavailableView("No active story", systemImage: "viewfinder", description: Text("Use AR Exp to reveal a story here."))
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private var checkpointList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tour checkpoints").font(.title3.bold())
            ForEach(Array(orderedCheckpoints.enumerated()), id: \.element.id) { index, checkpoint in
                Button {
                    onSelectCheckpoint(checkpoint)
                    selectedCheckpoint = checkpoint
                } label: {
                    HStack(spacing: 12) {
                        Text("\(checkpoint.order + 1)").font(.headline).foregroundStyle(.white).frame(width: 36, height: 36).background(Theme.primary, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checkpoint.name.v(session.language)).font(.headline)
                            Text(checkpoint.intro.v(session.language)).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
                        }
                        Spacer()
                        if let status = status(for: checkpoint, index: index) {
                            Text(LocalizedStringKey(status.title))
                                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                                .textCase(.uppercase)
                                .foregroundStyle(status.color)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(status.color.opacity(0.1), in: Capsule())
                        }
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Theme.primary)
                            .accessibilityHidden(true)
                    }.foregroundStyle(Theme.ink).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityHint("Opens an illustrated checkpoint guide")
            }
        }
    }

    private func status(for checkpoint: Checkpoint, index: Int) -> CheckpointInfoStatus? {
        if checkpoint.nuggets.allSatisfy({ visitedNuggetIDs.contains($0.id) }) { return .completed }
        if checkpoint.id == session.currentCheckpointID { return .current }
        guard index > 0 else { return nil }
        let previous = orderedCheckpoints[index - 1]
        return previous.nuggets.allSatisfy({ visitedNuggetIDs.contains($0.id) }) ? nil : .locked
    }
}

private struct CheckpointGuideSheet: View {
    let checkpoint: Checkpoint
    let language: String
    @Environment(\.dismiss) private var dismiss

    private var guide: CheckpointGuideContent {
        CheckpointGuideContent.content(for: checkpoint)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CheckpointArtwork(guide: guide)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("AI GUIDE OVERVIEW", systemImage: "sparkles")
                            .font(.caption.bold()).tracking(1)
                            .foregroundStyle(Theme.gold)
                        Text(checkpoint.name.v(language))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.primary)
                        Text(guide.description.v(language))
                            .font(.body).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHY IT MATTERS")
                            .font(.caption.bold()).tracking(1).foregroundStyle(Theme.teal)
                        Text(checkpoint.intro.v(language))
                            .foregroundStyle(Theme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background(Theme.surfaceLow)
            .navigationTitle("Checkpoint Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CheckpointArtwork: View {
    let guide: CheckpointGuideContent

    var body: some View {
        ZStack {
            LinearGradient(colors: guide.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 180, height: 180)
                .offset(x: 110, y: -65)
            Circle()
                .fill(.black.opacity(0.08))
                .frame(width: 140, height: 140)
                .offset(x: -130, y: 80)
            Image(systemName: guide.symbol)
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(Theme.goldLight)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
        }
        .overlay(alignment: .bottomLeading) {
            Text(guide.artworkLabel)
                .font(.caption.bold()).tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.25), in: Capsule())
                .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guide.artworkLabel)
    }
}

private struct CheckpointGuideContent {
    let symbol: String
    let artworkLabel: String
    let colors: [Color]
    let description: LangMap

    static func content(for checkpoint: Checkpoint) -> CheckpointGuideContent {
        switch checkpoint.id {
        case "cp_main_gate":
            CheckpointGuideContent(
                symbol: "archway",
                artworkLabel: "Gate illustration placeholder",
                colors: [Color(hex: 0x7A2D2E), Color(hex: 0xD17A52)],
                description: [
                    "en": "The Great Gate is more than an entrance: it carefully frames the Taj Mahal and controls the visitor's first reveal. Its red sandstone, white marble details, and increasingly large calligraphy use perspective to make the inscription appear evenly sized from the ground.",
                    "hi": "महान द्वार केवल प्रवेश मार्ग नहीं है; यह ताजमहल के पहले दृश्य को सावधानी से फ्रेम करता है। लाल बलुआ पत्थर, सफेद संगमरमर और ऊपर की ओर बड़े होते अक्षर जमीन से देखने पर लेख को समान आकार का दिखाते हैं।"
                ]
            )
        case "cp_charbagh":
            CheckpointGuideContent(
                symbol: "tree.fill",
                artworkLabel: "Garden illustration placeholder",
                colors: [Color(hex: 0x245C45), Color(hex: 0x8CB369)],
                description: [
                    "en": "Charbagh follows the Persian four-garden idea of paradise. Water channels divide the landscape into balanced sections, while the long reflecting pool strengthens the monument's symmetry and guides your eye toward the central dome.",
                    "hi": "चारबाग फारसी चार-बाग परंपरा में स्वर्ग की कल्पना प्रस्तुत करता है। जलमार्ग बगीचे को संतुलित भागों में बांटते हैं और लंबा प्रतिबिंबित जलकुंड नजर को मुख्य गुंबद की ओर ले जाता है।"
                ]
            )
        case "cp_main_platform":
            CheckpointGuideContent(
                symbol: "square.3.layers.3d",
                artworkLabel: "Marble platform illustration placeholder",
                colors: [Color(hex: 0x697A8A), Color(hex: 0xD9D7CF)],
                description: [
                    "en": "The marble platform lifts the mausoleum above the riverfront and joins the main tomb, mosque, and guest pavilion into one composition. Makrana marble scatters light beneath its surface, producing the soft glow that changes from dawn to moonlight.",
                    "hi": "संगमरमर का चबूतरा मकबरे को नदी किनारे से ऊपर उठाता है और मुख्य इमारत, मस्जिद तथा अतिथि मंडप को एक रचना में जोड़ता है। मकराना संगमरमर सतह के भीतर प्रकाश फैलाकर सुबह से चांदनी तक बदलती कोमल चमक पैदा करता है।"
                ]
            )
        default:
            CheckpointGuideContent(
                symbol: "photo.artframe",
                artworkLabel: "Checkpoint illustration placeholder",
                colors: [Theme.primary, Theme.gold],
                description: checkpoint.intro
            )
        }
    }
}

private enum CheckpointInfoStatus {
    case locked, current, completed

    var title: String {
        switch self { case .locked: "Locked"; case .current: "Current"; case .completed: "Completed" }
    }

    var color: Color {
        switch self { case .locked: Theme.mutedInk; case .current: Theme.primary; case .completed: Theme.teal }
    }
}
