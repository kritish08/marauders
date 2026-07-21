import SwiftData
import SwiftUI

struct TourContainerView: View {
    let booking: TourBooking
    @StateObject private var session: TourSession
    @StateObject private var tajProgressStore: TajTourProgressStore
    @StateObject private var audioPlayer = NuggetAudioPlayer()
    @StateObject private var ambientPlayer = AmbientAudioPlayer()
    @StateObject private var locationService = LocationService()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allVisits: [VisitedNugget]
    @State private var tab: TourTab = .map
    @State private var showBrowse = false
    @State private var showAmbientToast = false
    @State private var playedCheckpointIntros = Set<String>()
    @State private var showRecap = false
    @State private var liveActivity = TourLiveActivityController()
    @State private var showGiftLocked = false
    @State private var showGiftVoucher = false
    @State private var showAIGuide = false

    private var isTajJourney: Bool { session.installed.package.monument.id == "taj_mahal" }

    enum TourTab: CaseIterable {
        case map
        case scan
        case info

        var displayTitle: LocalizedStringResource {
            switch self {
            case .map: "Map"
            case .scan: "AR Exp"
            case .info: "Info"
            }
        }

        var accessibilityTitle: LocalizedStringResource {
            switch self {
            case .map: "Map"
            case .scan: "AR Experience"
            case .info: "Info"
            }
        }

        var icon: String {
            switch self { case .map: "map.fill"; case .scan: "viewfinder"; case .info: "info.circle.fill" }
        }

        var accessibilityID: String {
            switch self { case .map: "map"; case .scan: "scan"; case .info: "info" }
        }
    }

    init(booking: TourBooking, installed: InstalledTour, language: String) {
        self.booking = booking
        _session = StateObject(wrappedValue: TourSession(installed: installed, language: language))
        _tajProgressStore = StateObject(wrappedValue: TajTourProgressStore(scopeID: "\(installed.package.monument.id).\(booking.id)"))
    }

    private var visits: [VisitedNugget] {
        allVisits.filter { $0.monumentId == session.installed.package.monument.id }
    }

    private var totalNuggets: Int {
        session.installed.package.checkpoints.reduce(0) { $0 + $1.nuggets.count }
    }

    private var visitedNuggetIDs: Set<String> { Set(visits.map(\.id)) }

    private var isJourneyComplete: Bool {
        isTajJourney ? tajProgressStore.isComplete : (totalNuggets > 0 && visitedNuggetIDs.count >= totalNuggets)
    }

    private var liveActivityState: TourActivityAttributes.ContentState {
        TourActivityAttributes.ContentState(
            chapterName: isTajJourney
                ? (tajProgressStore.selectedChapter?.name ?? "Start (Entry)")
                : (session.currentCheckpoint?.name.v(session.language) ?? session.installed.package.monument.name.v(session.language)),
            completedChapters: isTajJourney ? tajProgressStore.completedChapterCount : min(visitedNuggetIDs.count, totalNuggets),
            totalChapters: isTajJourney ? tajProgressStore.totalChapterCount : totalNuggets,
            isNarrating: audioPlayer.isPlaying
        )
    }

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .map:
                    InteractiveMapView(
                        session: session,
                        tajProgressStore: tajProgressStore,
                        audioPlayer: audioPlayer,
                        ambientPlayer: ambientPlayer,
                        visitedNuggetIDs: visitedNuggetIDs,
                        selectedTab: $tab,
                        onBrowse: { showBrowse = true },
                        onSelectCheckpoint: selectCheckpoint
                    )
                case .scan:
                    ARCameraView(
                        session: session,
                        audioPlayer: audioPlayer,
                        ambientPlayer: ambientPlayer,
                        routeChapterName: isTajJourney ? tajProgressStore.selectedChapter?.name : nil,
                        routeTargetID: isTajJourney ? tajProgressStore.selectedChapter?.arAssetName : nil,
                        onBrowse: { showBrowse = true }
                    )
                case .info:
                    MonumentInfoView(
                        session: session,
                        audioPlayer: audioPlayer,
                        visitedNuggetIDs: visitedNuggetIDs,
                        onSelectCheckpoint: selectCheckpoint
                    )
                }
            }
            if showAmbientToast { ambientToast }
        }
        .safeAreaInset(edge: .top, spacing: 0) { isTajJourney ? AnyView(tajTripProgress) : AnyView(tripProgress) }
        .safeAreaInset(edge: .bottom, spacing: 0) { tourBar }
        .navigationTitle(session.installed.package.monument.name.v(session.language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    audioPlayer.stop()
                    showAIGuide = true
                } label: {
                    Image(systemName: "bubble.left.and.sparkles.fill")
                }
                .accessibilityLabel("Open AI Guide")
                .accessibilityIdentifier("openAIGuideButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if ambientPlayer.isAvailable {
                        Button { ambientPlayer.toggleMute() } label: {
                            Label(ambientPlayer.isMuted ? "Unmute ambient audio" : "Mute ambient audio", systemImage: ambientPlayer.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        }
                    }
                    if isTajJourney, tajProgressStore.completedChapterCount > 0 {
                        Button { showRecap = true } label: {
                            Label("Tour recap and quiz", systemImage: "book.pages.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Tour options")
            }
        }
        .fullScreenCover(isPresented: $showBrowse) {
            BrowseModeView(session: session, audioPlayer: audioPlayer, onEngage: engage)
        }
        .sheet(isPresented: $showRecap) {
            TourRecapView(
                completedChapters: tajProgressStore.chapters.filter { tajProgressStore.completedIDs.contains($0.id) },
                monumentName: session.installed.package.monument.name.v(session.language)
            )
        }
        .alert("Gift locked", isPresented: $showGiftLocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Complete the journey to unlock the gift card.")
        }
        .sheet(isPresented: $showGiftVoucher) {
            DistrictVoucherView()
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAIGuide) {
            AIGuideView(context: aiGuideContext)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .onAppear {
            audioPlayer.onStart = markVisited
            locationService.start()
            if ambientPlayer.start(installed: session.installed) {
                showAmbientToast = true
                Task {
                    try? await Task.sleep(for: .seconds(2.4))
                    if reduceMotion {
                        showAmbientToast = false
                    } else {
                        withAnimation { showAmbientToast = false }
                    }
                }
            }
            playCurrentCheckpointIntro()
            liveActivity.start(
                monumentName: session.installed.package.monument.name.v(session.language),
                state: liveActivityState
            )
        }
        .onDisappear {
            audioPlayer.stop()
            ambientPlayer.stop()
            locationService.stop()
            liveActivity.end()
        }
        .onChange(of: audioPlayer.isPlaying) { _, playing in
            ambientPlayer.setDucked(playing, for: .tourNarration)
            liveActivity.update(liveActivityState)
        }
        .onChange(of: tajProgressStore.completedChapterCount) { _, _ in
            liveActivity.update(liveActivityState)
        }
        .onChange(of: tajProgressStore.selectedChapter?.id) { _, _ in
            liveActivity.update(liveActivityState)
        }
        .onChange(of: visitedNuggetIDs.count) { _, _ in
            liveActivity.update(liveActivityState)
        }
        .onChange(of: tab) { _, selected in
            if selected == .map { playCurrentCheckpointIntro() }
        }
        .onChange(of: locationService.location) { _, _ in
            if let checkpoint = locationService.nearestCheckpoint(in: session.installed.package.checkpoints) {
                if reduceMotion { selectCheckpoint(checkpoint) } else { withAnimation { selectCheckpoint(checkpoint) } }
            }
        }
    }

    private var tripProgress: some View {
        let completed = min(visitedNuggetIDs.count, totalNuggets)
        let progress = totalNuggets == 0 ? 0 : Double(completed) / Double(totalNuggets)

        return VStack(spacing: 8) {
            HStack {
                Label("TRIP PROGRESS", systemImage: "figure.walk")
                    .font(.caption.bold()).tracking(0.8)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text("\(completed) of \(totalNuggets) secrets - \(Int(progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mutedInk)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trip progress")
            .accessibilityValue("\(completed) of \(totalNuggets) secrets discovered, \(Int(progress * 100)) percent")

            ZStack(alignment: .trailing) {
                ProgressView(value: progress)
                    .tint(Theme.gold)
                    .scaleEffect(y: 1.6)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
                Button { presentGift() } label: {
                    Image(systemName: isJourneyComplete ? "gift.fill" : "gift")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isJourneyComplete ? Theme.primary : Theme.mutedInk)
                        .frame(width: 44, height: 44)
                        .background(isJourneyComplete ? Theme.goldLight : Theme.surfaceContainer, in: Circle())
                        .overlay { Circle().stroke(Theme.gold.opacity(isJourneyComplete ? 0.85 : 0.35), lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isJourneyComplete ? "Gift card unlocked" : "Gift card locked")
                .accessibilityHint(isJourneyComplete ? "Shows your unlocked reward" : "Shows how to unlock the reward")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var tajTripProgress: some View {
        let completed = tajProgressStore.completedChapterCount
        let total = tajProgressStore.totalChapterCount
        let progress = tajProgressStore.progress
        let chapter = tajProgressStore.selectedChapter?.name ?? "Start (Entry)"

        return VStack(spacing: 8) {
            HStack {
                Label("TRIP PROGRESS", systemImage: "figure.walk")
                    .font(.caption.bold()).tracking(0.8).foregroundStyle(Theme.primary)
                Spacer()
                Text("\(completed) of \(total) chapters - \(Int(progress * 100))%")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
            }
            HStack {
                Text("Selected stop: \(chapter)").font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            ZStack(alignment: .trailing) {
                ProgressView(value: progress)
                    .tint(Theme.gold)
                    .scaleEffect(y: 1.6)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
                Button { presentGift() } label: {
                    Image(systemName: isJourneyComplete ? "gift.fill" : "gift")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isJourneyComplete ? Theme.primary : Theme.mutedInk)
                        .frame(width: 44, height: 44)
                        .background(isJourneyComplete ? Theme.goldLight : Theme.surfaceContainer, in: Circle())
                        .overlay { Circle().stroke(Theme.gold.opacity(isJourneyComplete ? 0.85 : 0.35), lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isJourneyComplete ? "Gift card unlocked" : "Gift card locked")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
        .accessibilityIdentifier("tajChapterProgress")
    }

    private var ambientToast: some View {
        Label("Ambient audio playing", systemImage: "music.note")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)
            .allowsHitTesting(false)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private var tourBar: some View {
        HStack {
            ForEach(TourTab.allCases, id: \.self) { item in
                Button {
                    if reduceMotion { tab = item } else { withAnimation(.snappy) { tab = item } }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 20, weight: .semibold))
                        Text(item.displayTitle).textCase(.uppercase).font(.caption2.bold()).tracking(0.7)
                    }
                    .foregroundStyle(tab == item ? Theme.primary : Theme.mutedInk.opacity(0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(tab == item ? Theme.goldLight.opacity(0.28) : .clear, in: Capsule())
                }
                .accessibilityIdentifier("tourTab_\(item.accessibilityID)")
                .accessibilityLabel(Text(item.accessibilityTitle))
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.1), radius: 12, y: -3)
    }

    private func markVisited(_ nuggetID: String) {
        guard !visitedNuggetIDs.contains(nuggetID),
              let checkpoint = session.checkpoint(containing: nuggetID) else { return }
        session.activeNuggetID = nuggetID
        session.currentCheckpointID = checkpoint.id
        modelContext.insert(VisitedNugget(
            id: nuggetID,
            checkpointId: checkpoint.id,
            monumentId: session.installed.package.monument.id
        ))
        try? modelContext.save()
    }

    private func engage(_ checkpoint: Checkpoint, _ nugget: Nugget) {
        session.select(checkpoint: checkpoint, nugget: nugget)
        audioPlayer.replay(nugget: nugget, language: session.language, directory: session.installed.directory)
    }

    private func selectCheckpoint(_ checkpoint: Checkpoint) {
        session.select(checkpoint: checkpoint)
        playCurrentCheckpointIntro()
    }

    private func playCurrentCheckpointIntro() {
        guard let checkpoint = session.currentCheckpoint,
              playedCheckpointIntros.insert(checkpoint.id).inserted else { return }
        let started = audioPlayer.playIntro(
            checkpoint: checkpoint,
            language: session.language,
            directory: session.installed.directory
        )
        if !started { playedCheckpointIntros.remove(checkpoint.id) }
    }

    private func presentGift() {
        if isJourneyComplete {
            showGiftVoucher = true
        } else {
            showGiftLocked = true
        }
    }

    private var aiGuideContext: AIGuideContext {
        let tajChapter = isTajJourney ? tajProgressStore.selectedChapter : nil
        let checkpointID = tajChapter.map { TajAIInsightStore.backendCheckpointID(forChapter: $0.id) }
            ?? session.currentCheckpointID
        return AIGuideContext(
            monumentID: session.installed.package.monument.id,
            monumentName: session.installed.package.monument.name.v(session.language),
            checkpointID: checkpointID,
            checkpointName: tajChapter?.name ?? session.currentCheckpoint?.name.v(session.language) ?? "this stop",
            language: session.language
        )
    }
}

private struct DistrictVoucherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gift.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 72, height: 72)
                .background(Theme.goldLight.opacity(0.5), in: Circle())

            VStack(spacing: 8) {
                Text("Hurrah!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("Hope you had a wonderful experience!")
                    .font(.headline).foregroundStyle(Theme.ink)
                Text("Here is a 10% voucher for your next District purchase.")
                    .font(.subheadline).foregroundStyle(Theme.mutedInk)
                    .multilineTextAlignment(.center)
            }

            Button {
                guard let url = URL(string: "https://www.district.in/") else { return }
                openURL(url)
            } label: {
                Label("Activate Deal", systemImage: "arrow.up.right.square.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("activateDistrictDealButton")

            Button("Not Now") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.mutedInk)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surfaceLow)
    }
}
