import ARKit
import AVFoundation
import SwiftUI
import TipKit
import UIKit

struct ARCameraView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var session: TourSession
    @ObservedObject var audioPlayer: NuggetAudioPlayer
    @ObservedObject var ambientPlayer: AmbientAudioPlayer
    let routeChapterName: String?
    let routeTargetID: String?
    let onBrowse: () -> Void
    @StateObject private var question = VoiceQuestionService()
    @State private var cameraAuthorized: Bool?
    @State private var arFailed = false
    @State private var revealedNugget: Nugget?
    @State private var frozenFrame: UIImage?
    @State private var shutterFlash = false
    @State private var showTextChat = false
    @StateObject private var vision = VisionAnswerService()
    @State private var visionSnapshot: UIImage?
    private let snapshotProxy = CameraSnapshotProxy()

    private var arReady: Bool {
        ARImageTrackingConfiguration.isSupported && cameraAuthorized == true && !arFailed
    }

    private var suppressesARInteraction: Bool {
        question.suppressesTourAudio || showTextChat || visionSnapshot != nil
    }

    private var allowedTargetIDs: Set<String>? {
        guard let routeTargetID else { return nil }
        let nugget = session.installed.package.checkpoints
            .flatMap(\.nuggets)
            .first { $0.effectiveTargetImageIds.contains(routeTargetID) }
        return Set(nugget?.effectiveTargetImageIds ?? [routeTargetID])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer

            if let nugget = revealedNugget {
                NuggetRevealCard(
                    session: session,
                    nugget: nugget,
                    audioPlayer: audioPlayer,
                    onReplay: { audioPlayer.replay(nugget: nugget, language: session.language, directory: session.installed.directory) },
                    onClose: { withAnimation(reduceMotion ? nil : .snappy) { revealedNugget = nil } }
                )
                .transition(.opacity)
                .zIndex(2)
            } else if arReady {
                cameraOverlay.zIndex(1)
            }

            if shutterFlash { shutterFeedback.zIndex(5) }
        }
        .task { await requestCameraAccess() }
        .sheet(isPresented: $showTextChat) {
            AIGuideView(context: AIGuideContext(
                monumentID: session.installed.package.monument.id,
                monumentName: session.installed.package.monument.name.v(session.language),
                checkpointID: session.currentCheckpoint?.id ?? session.installed.package.checkpoints.first?.id ?? "cp_great_gate",
                checkpointName: session.currentCheckpoint?.name.v(session.language) ?? "this stop",
                language: session.language
            ))
        }
        .sheet(isPresented: Binding(
            get: { visionSnapshot != nil },
            set: { if !$0 { visionSnapshot = nil; vision.reset() } }
        )) {
            WhatsThisSheet(snapshot: visionSnapshot, vision: vision)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: question.suppressesTourAudio) { _, suppressed in
            ambientPlayer.setDucked(suppressed, for: .liveQuestion)
        }
        .onDisappear {
            question.cancel()
            ambientPlayer.setDucked(false, for: .liveQuestion)
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if !ARImageTrackingConfiguration.isSupported {
            browseFallback(title: "AR is unavailable", message: "All package stories remain available in Audio Exp. Return to the map to complete chapters.")
        } else if cameraAuthorized == true, !arFailed {
            ARImageTrackingView(
                session: session,
                isSuppressed: suppressesARInteraction,
                allowedTargetIDs: allowedTargetIDs,
                snapshotProxy: snapshotProxy,
                onFound: found,
                onLost: lost,
                onFailure: { arFailed = true }
            )
            .ignoresSafeArea()
            .clipShape(RoundedRectangle(cornerRadius: revealedNugget == nil ? 0 : 90, style: .continuous))
            .scaleEffect(revealedNugget == nil ? 1 : 0.25, anchor: .topTrailing)
            .offset(x: revealedNugget == nil ? 0 : -16, y: revealedNugget == nil ? 0 : 64)
            .allowsHitTesting(revealedNugget == nil)
            .shadow(color: .black.opacity(revealedNugget == nil ? 0 : 0.32), radius: 14)
            .animation(reduceMotion ? nil : .snappy, value: revealedNugget?.id)
            .zIndex(revealedNugget == nil ? 0 : 4)
        } else if cameraAuthorized == false {
            browseFallback(title: "Camera access is off", message: "All package stories remain available in Audio Exp. Return to the map to complete chapters.", showsSettings: true)
        } else if arFailed {
            browseFallback(title: "AR could not start", message: "Continue with package stories in Audio Exp, then return to the map to complete this chapter.")
        } else {
            ProgressView("Preparing AR camera…").tint(.white).foregroundStyle(.white)
        }
    }

    private var cameraOverlay: some View {
        Group {
            if verticalSizeClass == .compact {
                compactCameraOverlay
            } else {
                regularCameraOverlay
            }
        }
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom))
    }

    private var regularCameraOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                cameraTitle
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    browseButton
                    whatsThisButton
                }
            }.padding(20)

            Spacer()
            scanGuide
            Spacer()
            Text("Hold a printed target steady to reveal its story")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12).glassCapsule()

            questionStatus
            HStack(spacing: 26) {
                textChatButton
                questionButton
                textChatButton.hidden()
            }
            .padding(.top, 12).padding(.bottom, 106)
        }
    }

    private var compactCameraOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                cameraTitle
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    browseButton
                    whatsThisButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 4)
            compactScanGuide
            Spacer(minLength: 4)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hold a printed target steady to reveal its story")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8).glassCapsule()
                    questionStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                textChatButton
                questionButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var cameraTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIVE AR").font(.caption.bold()).tracking(1.3).foregroundStyle(Theme.goldLight)
            Text(routeChapterName ?? session.currentCheckpoint?.name.v(session.language) ?? session.installed.package.monument.name.v(session.language))
                .font(.headline).foregroundStyle(.white).lineLimit(2)
        }
    }

    private var browseButton: some View {
        Button(action: onBrowse) {
            Label("Audio Exp", systemImage: "headphones")
                .font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .glassCapsule()
                .contentShape(Capsule())
        }
        .accessibilityIdentifier("cameraBrowseButton")
    }

    // Image tracking degrades fast past ~35° off-axis; guide users to line up
    // straight-on instead of trying oblique angles the tech can't match.
    private var scanGuide: some View {
        VStack(spacing: 10) {
            Image(systemName: "viewfinder")
                .font(.system(size: 190, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.5))
            Label("Face the artwork straight-on and fill the frame", systemImage: "camera.metering.center.weighted")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassCapsule()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var compactScanGuide: some View {
        Label("Face the artwork straight-on and fill the frame", systemImage: "viewfinder")
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassCapsule()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var whatsThisButton: some View {
        Button {
            guard let frame = snapshotProxy.capture?() else { return }
            audioPlayer.stop()
            visionSnapshot = frame
            vision.identify(
                image: frame,
                monumentName: session.installed.package.monument.name.v(session.language),
                checkpointID: session.currentCheckpoint?.id ?? session.installed.package.checkpoints.first?.id ?? "cp_great_gate",
                monumentID: session.installed.package.monument.id,
                lang: session.language
            )
        } label: {
            Label("What's this?", systemImage: "sparkle.magnifyingglass")
                .font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .glassCapsule()
                .contentShape(Capsule())
        }
        .popoverTip(WhatsThisTip(), arrowEdge: .top)
        .accessibilityIdentifier("whatsThisButton")
    }

    private var textChatButton: some View {
        Button {
            audioPlayer.stop()
            showTextChat = true
        } label: {
            Image(systemName: "keyboard.fill")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
        .popoverTip(TextChatTip(), arrowEdge: .bottom)
        .accessibilityLabel("Ask the guide by text")
        .accessibilityIdentifier("textQuestionButton")
    }

    private var questionButton: some View {
        Button {
            guard let checkpoint = session.currentCheckpoint else { return }
            audioPlayer.stop()
            ambientPlayer.setDucked(true, for: .liveQuestion)
            question.toggleRecording(
                checkpointID: checkpoint.id,
                monumentID: session.installed.package.monument.id,
                language: session.language
            )
        } label: {
            Image(systemName: question.state == .recording ? "stop.fill" : "mic.fill")
                .font(.title2).foregroundStyle(question.state == .recording ? Theme.primary : .white)
                .frame(width: 72, height: 72)
                .background(question.state == .recording ? Color.white : Theme.primary, in: Circle())
                .overlay { Circle().stroke(.white, lineWidth: 4).padding(5) }
        }
        .disabled(question.state == .thinking || question.state == .speaking || question.state == .requestingPermission)
        .opacity(question.state == .thinking || question.state == .speaking ? 0.55 : 1)
        .accessibilityLabel(questionAccessibilityLabel)
        .accessibilityIdentifier("liveQuestionButton")
    }

    private var questionAccessibilityLabel: String {
        switch question.state {
        case .requestingPermission:
            "Preparing microphone"
        case .recording:
            "Stop recording and send question"
        case .thinking:
            "Guide is thinking"
        case .speaking:
            "Guide is answering"
        case .failed, .idle:
            "Ask the guide by voice"
        }
    }

    @ViewBuilder
    private var questionStatus: some View {
        switch question.state {
        case .requestingPermission:
            Text("Preparing microphone…").statusPill(color: Theme.gold)
        case .recording:
            Text("Listening… Tap to send").statusPill(color: .red)
        case .thinking:
            Label("Guide is thinking…", systemImage: "ellipsis.bubble").statusPill(color: Theme.gold)
        case .speaking:
            Text(question.answerText ?? "Answering…").statusPill(color: Theme.teal)
        case .failed(let message):
            Button {
                guard let checkpoint = session.currentCheckpoint else { return }
                audioPlayer.stop()
                ambientPlayer.setDucked(true, for: .liveQuestion)
                question.retry(checkpointID: checkpoint.id, monumentID: session.installed.package.monument.id, language: session.language)
            } label: {
                Label(message + " Tap to retry.", systemImage: "arrow.clockwise").statusPill(color: Theme.primary)
            }
        case .idle:
            EmptyView()
        }
    }

    private var shutterFeedback: some View {
        ZStack {
            if let frozenFrame {
                Image(uiImage: frozenFrame).resizable().scaledToFill().ignoresSafeArea()
            }
            Color.white.opacity(0.88).ignoresSafeArea()
        }.allowsHitTesting(false)
    }

    private func browseFallback(title: String, message: String, showsSettings: Bool = false) -> some View {
        VStack(spacing: 17) {
            Image(systemName: "headphones").font(.system(size: 48)).foregroundStyle(Theme.goldLight)
            Text(title).font(.title2.bold()).foregroundStyle(.white)
            Text(message).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            Button("Open Audio Exp", action: onBrowse)
                .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 280).accessibilityIdentifier("fallbackBrowseButton")
            if showsSettings {
                Button("Open Camera Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.foregroundStyle(.white)
            }
        }.padding(30).padding(.bottom, 100)
    }

    private func found(_ checkpoint: Checkpoint, _ nugget: Nugget, _ frame: UIImage?) {
        guard !suppressesARInteraction else { return }
        session.select(checkpoint: checkpoint, nugget: nugget)
        audioPlayer.targetFound(nugget: nugget, language: session.language, directory: session.installed.directory)
        guard revealedNugget?.id != nugget.id else { return }
        frozenFrame = frame
        shutterFlash = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !suppressesARInteraction else {
                shutterFlash = false
                frozenFrame = nil
                return
            }
            shutterFlash = false
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { revealedNugget = nugget }
            frozenFrame = nil
        }
    }

    private func lost(_ nugget: Nugget) {
        guard !suppressesARInteraction else { return }
        audioPlayer.targetLost(nuggetID: nugget.id)
    }

    private func requestCameraAccess() async {
        guard ARImageTrackingConfiguration.isSupported else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraAuthorized = true
        case .notDetermined: cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: cameraAuthorized = false
        @unknown default: cameraAuthorized = false
        }
    }
}

private extension View {
    func statusPill(color: Color) -> some View {
        self.font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
            .padding(.horizontal, 14).padding(.vertical, 9).background(color.opacity(0.88), in: Capsule()).padding(.top, 10)
    }
}

private struct WhatsThisSheet: View {
    let snapshot: UIImage?
    @ObservedObject var vision: VisionAnswerService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable().scaledToFill()
                        .frame(height: 220).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                HStack {
                    Label("What's this?", systemImage: "sparkle.magnifyingglass")
                        .font(.headline).foregroundStyle(Theme.primary)
                    Spacer()
                    if VisionAnswerService.supportsOnDeviceVision {
                        Label("On-device", systemImage: "cpu.fill")
                            .font(.caption2.bold()).foregroundStyle(Theme.teal)
                    }
                }
                switch vision.state {
                case .idle, .thinking:
                    HStack { ProgressView(); Text("The guide is looking closely…") }
                        .foregroundStyle(Theme.mutedInk)
                case .answered(let text):
                    Text(text)
                        .foregroundStyle(Theme.ink).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("whatsThisAnswer")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(20)
        }
        .presentationBackground(Theme.surfaceLow)
    }
}
