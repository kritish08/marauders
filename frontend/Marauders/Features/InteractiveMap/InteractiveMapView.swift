import SwiftUI

struct InteractiveMapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: TourSession
    @ObservedObject var tajProgressStore: TajTourProgressStore
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    @ObservedObject var ambientPlayer: AmbientAudioPlayer
    let visitedNuggetIDs: Set<String>
    @Binding var selectedTab: TourContainerView.TourTab
    let onBrowse: () -> Void
    let onSelectCheckpoint: (Checkpoint) -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var completionBurst = false
    @State private var presentedTajChapter: TajMapCheckpoint?
    @State private var presentedCheckpoint: Checkpoint?
    @State private var lockedChapterName = ""
    @State private var showLockedChapter = false
    @State private var pendingTajDestination: TajDestination?
    @StateObject private var tajInsights = TajAIInsightStore()
    @StateObject private var narrator = AudioNarrationController()

    private var ordered: [Checkpoint] { session.installed.package.checkpoints.sorted { $0.order < $1.order } }
    private var isTajJourney: Bool { session.installed.package.monument.id == "taj_mahal" }
    private var isZomatoJourney: Bool { session.installed.package.monument.id == "zomato_farmhouse" }
    private var allCheckpointsCompleted: Bool { !ordered.isEmpty && ordered.allSatisfy(isCompleted) }

    var body: some View {
        GeometryReader { proxy in
            let mapSize = fittedMapSize(in: proxy.size)
            ZStack {
                Theme.surfaceContainer.ignoresSafeArea()
                ZStack {
                    Image(mapImageName)
                        .resizable().scaledToFit().frame(width: mapSize.width, height: mapSize.height)
                    if isTajJourney {
                        tajRoute(in: mapSize)
                        tajCheckpoints(in: mapSize)
                    } else {
                        trail(in: mapSize)
                        checkpoints(in: mapSize, viewport: proxy.size)
                    }
                    completionShimmer(in: mapSize)
                }
                .frame(width: mapSize.width, height: mapSize.height)
                .scaleEffect(scale).offset(offset)
                .gesture(mapGesture(viewport: proxy.size, mapSize: mapSize))
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { resetMap() }
                )
                controls(viewport: proxy.size, mapSize: mapSize)
            }
            .clipped()
            .onChange(of: proxy.size) { _, newSize in
                offset = clamped(offset, scale: scale, viewport: newSize, mapSize: fittedMapSize(in: newSize))
                lastOffset = offset
            }
            .onChange(of: session.currentCheckpointID) { _, id in
                guard let checkpoint = ordered.first(where: { $0.id == id }) else { return }
                focus(checkpoint, viewport: proxy.size, mapSize: mapSize)
            }
            .onChange(of: allCheckpointsCompleted) { wasComplete, isComplete in
                guard isZomatoJourney, !wasComplete, isComplete else { return }
                completionBurst = true
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    if reduceMotion {
                        completionBurst = false
                    } else {
                        withAnimation(.easeOut(duration: 0.6)) { completionBurst = false }
                    }
                }
            }
            .sheet(item: $presentedTajChapter, onDismiss: handleTajChapterDismissal) { chapter in
                TajCheckpointDetailView(
                    chapterID: chapter.id,
                    language: session.language,
                    progressStore: tajProgressStore,
                    insights: tajInsights,
                    narrator: narrator,
                    audioPlayer: audioPlayer,
                    ambientPlayer: ambientPlayer,
                    onOpenAR: {
                        selectPackageCheckpoint(for: chapter)
                        pendingTajDestination = .ar
                        presentedTajChapter = nil
                    },
                    onOpenBrowse: {
                        selectPackageCheckpoint(for: chapter)
                        pendingTajDestination = .browse
                        presentedTajChapter = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(item: $presentedCheckpoint, onDismiss: performPendingTajDestination) { checkpoint in
                CheckpointDetailSheet(
                    checkpoint: checkpoint,
                    language: session.language,
                    visitedCount: visitedCount(checkpoint),
                    onOpenAR: {
                        pendingTajDestination = .ar
                        presentedCheckpoint = nil
                    },
                    onOpenBrowse: {
                        pendingTajDestination = .browse
                        presentedCheckpoint = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .alert("Chapter locked", isPresented: $showLockedChapter) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Complete the previous chapter before opening \(lockedChapterName).")
            }
        }
    }

    private func performPendingTajDestination() {
        guard let destination = pendingTajDestination else { return }
        pendingTajDestination = nil
        switch destination {
        case .ar: selectedTab = .scan
        case .browse: onBrowse()
        }
    }

    private func handleTajChapterDismissal() {
        narrator.stop()
        ambientPlayer.setDucked(false, for: .checkpointSpeech)
        performPendingTajDestination()
    }

    private func selectPackageCheckpoint(for chapter: TajMapCheckpoint) {
        let checkpoint = ordered.first { $0.id == TajAIInsightStore.backendCheckpointID(forChapter: chapter.id) }
            ?? chapter.arAssetName.flatMap { targetID in
                ordered.first { checkpoint in
                    checkpoint.nuggets.contains { $0.effectiveTargetImageIds.contains(targetID) }
                }
            }
        if let checkpoint { session.select(checkpoint: checkpoint) }
    }

    private func tajRoute(in size: CGSize) -> some View {
        let stops = tajProgressStore.chapters
        return Canvas { context, _ in
            guard stops.count > 1 else { return }
            for index in 0..<(stops.count - 1) {
                var segment = Path()
                segment.move(to: stops[index].point(in: size))
                segment.addLine(to: stops[index + 1].point(in: size))
                let completed = stops[index + 1].status == .completed
                context.stroke(
                    segment,
                    with: .color(completed ? Theme.teal : Theme.gold.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: completed ? [] : [7, 7])
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tajCheckpoints(in size: CGSize) -> some View {
        ZStack {
            ForEach(tajProgressStore.chapters) { checkpoint in
                let point = checkpoint.point(in: size)
                let labelOffset: CGFloat = checkpoint.order.isMultiple(of: 2) || checkpoint.order == 5 ? -29 : 29
                Button {
                    guard checkpoint.status != .locked else {
                        lockedChapterName = checkpoint.name
                        showLockedChapter = true
                        return
                    }
                    let selection = {
                        guard tajProgressStore.select(checkpoint.id),
                              let selected = tajProgressStore.chapters.first(where: { $0.id == checkpoint.id }) else { return }
                        presentedTajChapter = selected
                    }
                    if reduceMotion { selection() } else { withAnimation(.spring(response: 0.38, dampingFraction: 0.82), selection) }
                } label: {
                    ZStack {
                        Circle().fill(.clear).frame(width: 52, height: 52)
                        Circle()
                            .fill(checkpoint.status.color)
                            .frame(width: checkpoint.status == .active ? 38 : 31, height: checkpoint.status == .active ? 38 : 31)
                            .overlay { Circle().stroke(.white, lineWidth: 3) }
                            .shadow(color: checkpoint.status.color.opacity(0.5), radius: 7, y: 3)
                        Image(systemName: checkpoint.status.icon)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .position(point)
                .accessibilityLabel("Route stop \(checkpoint.order + 1) of 6, \(checkpoint.name)")
                .accessibilityValue(checkpoint.status.label)
                .accessibilityHint(checkpoint.status == .locked ? "Complete the previous chapter to unlock" : "Opens chapter details")
                .accessibilityIdentifier("tajRouteCheckpoint_\(checkpoint.id)")

                Text(checkpoint.name)
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface.opacity(0.94), in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .position(x: point.x, y: point.y + labelOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var mapImageName: String {
        switch session.installed.package.monument.id {
        case "national_war_memorial": "WarMemorialMap"
        case "zomato_farmhouse": "ZomatoFarmMap"
        default: "TajMahalMap"
        }
    }

    @ViewBuilder
    private func trail(in size: CGSize) -> some View {
        if isZomatoJourney {
            dynamicTrail(in: size)
        } else {
            staticTrail(in: size)
        }
    }

    private func staticTrail(in size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path()
            for (index, checkpoint) in ordered.enumerated() {
                let point = CGPoint(x: size.width * checkpoint.mapPosition.x, y: size.height * checkpoint.mapPosition.y)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(Theme.gold.opacity(0.72)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [6, 8]))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dynamicTrail(in size: CGSize) -> some View {
        Group {
            if reduceMotion {
                dynamicTrailLayer(in: size, elapsed: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    dynamicTrailLayer(in: size, elapsed: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dynamicTrailLayer(in size: CGSize, elapsed: TimeInterval?) -> some View {
        let travel = elapsed.map { $0.truncatingRemainder(dividingBy: 2.4) / 2.4 }
        let breathe = elapsed.map { 0.78 + 0.16 * (0.5 + 0.5 * sin($0 * 1.8)) } ?? 0.86

        return Canvas { context, _ in
            guard ordered.count > 1 else { return }
            for index in 0..<(ordered.count - 1) {
                let source = ordered[index]
                let destination = ordered[index + 1]
                let start = point(for: source, in: size)
                let end = point(for: destination, in: size)
                var segment = Path()
                segment.move(to: start)
                segment.addLine(to: end)

                let sourceComplete = isCompleted(source)
                let destinationReached = isCompleted(destination) || destination.id == session.currentCheckpointID
                let completed = sourceComplete && destinationReached
                let active = sourceComplete && !destinationReached

                if completed || allCheckpointsCompleted {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Theme.gold.opacity(0.55), radius: 5))
                        layer.stroke(segment, with: .color(Theme.gold.opacity(breathe)), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 8]))
                    }
                    if let travel {
                        drawParticle(context: context, from: start, to: end, progress: travel, opacity: 0.62)
                    }
                } else if active {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Theme.goldLight.opacity(0.8), radius: 7))
                        layer.stroke(segment, with: .color(Theme.goldLight), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 8], dashPhase: -CGFloat((elapsed ?? 0) * 18)))
                    }
                    if let travel {
                        drawParticle(context: context, from: start, to: end, progress: travel, opacity: 1)
                        drawParticle(context: context, from: start, to: end, progress: (travel + 0.34).truncatingRemainder(dividingBy: 1), opacity: 0.55)
                    }
                } else {
                    context.stroke(segment, with: .color(Theme.mutedInk.opacity(0.18)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 9]))
                }
            }
        }
    }

    @ViewBuilder
    private func checkpoints(in size: CGSize, viewport: CGSize) -> some View {
        if isZomatoJourney, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let pulse = timeline.date.timeIntervalSinceReferenceDate
                checkpointLayer(in: size, viewport: viewport, pulse: pulse)
            }
        } else {
            checkpointLayer(in: size, viewport: viewport, pulse: nil)
        }
    }

    private func checkpointLayer(in size: CGSize, viewport: CGSize, pulse: TimeInterval?) -> some View {
        ZStack {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, checkpoint in
                let state = checkpointState(checkpoint, index: index)
                let wave = pulse.map { CGFloat(sin($0 * 2.2)) } ?? 0
                let markerScale: CGFloat = state == .current ? 1.025 + wave * 0.025 : (state == .visited ? 1.008 + wave * 0.008 : 1)
                Button { select(checkpoint, state: state, viewport: viewport, mapSize: size) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if state == .current, isZomatoJourney {
                                Circle()
                                    .stroke(Theme.goldLight.opacity(0.3 - Double(wave) * 0.08), lineWidth: 2)
                                    .frame(width: 52, height: 52)
                                    .scaleEffect(1.08 + wave * 0.08)
                            }
                            Circle().fill(state.color).frame(width: state == .current ? 42 : 34, height: state == .current ? 42 : 34)
                            Image(systemName: state.icon).font(.caption.bold()).foregroundStyle(.white)
                        }
                        .scaleEffect(markerScale)
                        .overlay { Circle().stroke(.white, lineWidth: 3) }
                        .shadow(color: state.color.opacity(state == .current && isZomatoJourney ? 0.68 : 0.45), radius: state == .current && isZomatoJourney ? 12 : 8)
                        Text(checkpoint.name.v(session.language))
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.surface.opacity(0.94), in: Capsule())
                    }
                }
                .disabled(state == .locked)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        select(checkpoint, state: state, viewport: viewport, mapSize: size)
                    }
                )
                .position(x: size.width * checkpoint.mapPosition.x, y: size.height * checkpoint.mapPosition.y)
                .accessibilityLabel("Checkpoint \(index + 1) of \(ordered.count), \(checkpoint.name.v(session.language))")
                .accessibilityValue(
                    Text(state.accessibilityValue)
                        + Text(", \(visitedCount(checkpoint)) of \(checkpoint.nuggets.count) stories visited")
                )
                .accessibilityHint(state == .locked ? "Complete the previous checkpoint to unlock" : "Opens checkpoint details")
                .accessibilityIdentifier("checkpoint_\(checkpoint.id)")
            }
        }.frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func completionShimmer(in size: CGSize) -> some View {
        if isZomatoJourney, completionBurst, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                LinearGradient(
                    colors: [.clear, Theme.goldLight.opacity(0.15), .white.opacity(0.34), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(-12))
                .offset(x: (CGFloat(progress) * 2 - 1) * size.width)
                .blendMode(.screen)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func controls(viewport: CGSize, mapSize: CGSize) -> some View {
        VStack(spacing: 9) {
            Button { zoom(0.4, viewport: viewport, mapSize: mapSize) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .accessibilityLabel("Zoom in")
            Button { zoom(-0.4, viewport: viewport, mapSize: mapSize) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                .accessibilityLabel("Zoom out")
            Button { resetMap() } label: { Image(systemName: "location.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("Reset map position and zoom")
        }
        .font(.headline).foregroundStyle(Theme.primary).padding(11).background(.ultraThinMaterial, in: Capsule()).shadow(radius: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(16)
    }

    private func mapGesture(viewport: CGSize, mapSize: CGSize) -> some Gesture {
        MagnifyGesture().onChanged { value in
            scale = min(max(lastScale * value.magnification, 1), 3.5)
            offset = clamped(offset, scale: scale, viewport: viewport, mapSize: mapSize)
        }
            .onEnded { _ in
                lastScale = scale
                offset = clamped(offset, scale: scale, viewport: viewport, mapSize: mapSize)
                lastOffset = offset
            }
            .simultaneously(with: DragGesture().onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                offset = clamped(proposed, scale: scale, viewport: viewport, mapSize: mapSize)
            }.onEnded { _ in lastOffset = offset })
    }

    private func fittedMapSize(in available: CGSize) -> CGSize {
        let ratio = mapAspectRatio
        let widthAtFullHeight = available.height * ratio
        if widthAtFullHeight <= available.width {
            return CGSize(width: widthAtFullHeight, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / ratio)
    }

    private func point(for checkpoint: Checkpoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * checkpoint.mapPosition.x, y: size.height * checkpoint.mapPosition.y)
    }

    private func isCompleted(_ checkpoint: Checkpoint) -> Bool {
        !checkpoint.nuggets.isEmpty && checkpoint.nuggets.allSatisfy { visitedNuggetIDs.contains($0.id) }
    }

    private func drawParticle(context: GraphicsContext, from start: CGPoint, to end: CGPoint, progress: Double, opacity: Double) {
        let amount = CGFloat(progress)
        let x = start.x + (end.x - start.x) * amount
        let y = start.y + (end.y - start.y) * amount
        let rect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: rect), with: .color(Theme.goldLight.opacity(opacity)))
    }

    private func visitedCount(_ checkpoint: Checkpoint) -> Int { checkpoint.nuggets.filter { visitedNuggetIDs.contains($0.id) }.count }

    private func checkpointState(_ checkpoint: Checkpoint, index: Int) -> CheckpointVisualState {
        if checkpoint.id == session.currentCheckpointID { return .current }
        if visitedCount(checkpoint) == checkpoint.nuggets.count { return .visited }
        if index == 0 { return .available }
        let previous = ordered[index - 1]
        return visitedCount(previous) == previous.nuggets.count ? .available : .locked
    }

    private func select(_ checkpoint: Checkpoint, state: CheckpointVisualState, viewport: CGSize, mapSize: CGSize) {
        guard state != .locked else { return }
        let selection = {
            onSelectCheckpoint(checkpoint)
            presentedCheckpoint = checkpoint
            focus(checkpoint, viewport: viewport, mapSize: mapSize)
        }
        if reduceMotion { selection() } else { withAnimation(.spring(response: 0.42, dampingFraction: 0.86), selection) }
    }

    private func zoom(_ amount: CGFloat, viewport: CGSize, mapSize: CGSize) {
        let changes = {
            scale = min(max(scale + amount, 1), 3.5)
            offset = clamped(offset, scale: scale, viewport: viewport, mapSize: mapSize)
            if scale == 1 { offset = .zero }
            lastScale = scale
            lastOffset = offset
        }
        if reduceMotion { changes() } else { withAnimation(.snappy, changes) }
    }

    private func resetMap() {
        let changes = {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
        if reduceMotion { changes() } else { withAnimation(.snappy, changes) }
    }

    private func focus(_ checkpoint: Checkpoint, viewport: CGSize, mapSize: CGSize) {
        guard scale > 1 else { return }
        let point = CGPoint(x: mapSize.width * checkpoint.mapPosition.x, y: mapSize.height * checkpoint.mapPosition.y)
        let centered = CGSize(
            width: -(point.x - mapSize.width / 2) * scale,
            height: -(point.y - mapSize.height / 2) * scale
        )
        offset = clamped(centered, scale: scale, viewport: viewport, mapSize: mapSize)
        lastOffset = offset
    }

    private func clamped(_ proposed: CGSize, scale: CGFloat, viewport: CGSize, mapSize: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let maxX = max((mapSize.width * scale - viewport.width) / 2, 0)
        let maxY = max((mapSize.height * scale - viewport.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private var mapAspectRatio: CGFloat {
        switch session.installed.package.monument.id {
        case "taj_mahal": 1024 / 1536
        case "national_war_memorial": 470 / 780
        case "zomato_farmhouse": 474 / 784
        default: 1024 / 1536
        }
    }
}

private enum CheckpointVisualState: Equatable {
    case locked, available, current, visited
    var color: Color { switch self { case .locked: .gray; case .available: Theme.gold; case .current: Theme.primary; case .visited: Theme.teal } }
    var icon: String { switch self { case .locked: "lock.fill"; case .available: "circle.fill"; case .current: "location.fill"; case .visited: "checkmark" } }
    var accessibilityValue: LocalizedStringKey { switch self { case .locked: "Locked"; case .available: "Available"; case .current: "Current"; case .visited: "Visited" } }
}

private enum TajDestination { case ar, browse }

private struct CheckpointDetailSheet: View {
    let checkpoint: Checkpoint
    let language: String
    let visitedCount: Int
    let onOpenAR: () -> Void
    let onOpenBrowse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("CHECKPOINT \(checkpoint.order + 1)", systemImage: "mappin.circle.fill")
                                .font(.caption.bold()).tracking(1).foregroundStyle(Theme.gold)
                            Spacer()
                            Text("\(visitedCount)/\(checkpoint.nuggets.count) STORIES")
                                .font(.caption2.bold()).foregroundStyle(Theme.teal)
                        }
                        Text(checkpoint.name.v(language))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("A location-specific stop in your guided route.")
                            .foregroundStyle(Theme.mutedInk)
                    }
                    .padding(18)
                    .heritageCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Label("About this stop", systemImage: "book.closed.fill")
                            .font(.headline).foregroundStyle(Theme.primary)
                        Text(checkpoint.intro.v(language))
                            .foregroundStyle(Theme.mutedInk).lineSpacing(4)
                    }
                    .padding(18)
                    .heritageCard()

                    actionLayout {
                        Button(action: onOpenBrowse) {
                            actionLabel("Stories", icon: "headphones")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.primary)
                        .accessibilityIdentifier("browseCheckpointButton")

                        Button(action: onOpenAR) {
                            actionLabel("AR", icon: "viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)

                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Theme.surfaceLow)
            .navigationTitle("Checkpoint \(checkpoint.order + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var actionLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(spacing: 8))
        } else {
            AnyLayout(HStackLayout(spacing: 8))
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(title).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
    }
}
