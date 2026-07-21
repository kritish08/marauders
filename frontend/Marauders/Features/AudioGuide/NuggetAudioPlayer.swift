import AVFoundation
import Foundation

enum NuggetAudio: Equatable {
    case idle
    case entering(Date)
    case playing(String)
    case exiting(Date)
}

enum AudioTiming {
    static let enterHold: TimeInterval = 0.3
    static let exitHold: TimeInterval = 1.5
    static let fadeIn: TimeInterval = 0.4
    static let fadeOut: TimeInterval = 0.6
    static let crossfade: TimeInterval = 0.5
}

@MainActor
final class NuggetAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var state: NuggetAudio = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var onStart: ((String) -> Void)?
    private var player: AVAudioPlayer?
    private var enterTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var pendingNuggetID: String?
    private var activeNuggetID: String?
    private var currentPlaybackID: String?

    func targetFound(nugget: Nugget, language: String, directory: URL) {
        if activeNuggetID == nugget.id, let player {
            exitTask?.cancel()
            exitTask = nil
            fadeTask?.cancel()
            fadeTask = nil
            player.setVolume(1, fadeDuration: AudioTiming.fadeIn)
            if !player.isPlaying { isPlaying = player.play() }
            state = .playing(nugget.id)
            return
        }
        if case .playing(let id) = state, id == nugget.id { return }
        if pendingNuggetID == nugget.id { return }

        pendingNuggetID = nugget.id
        let enteredAt = Date()
        state = .entering(enteredAt)
        enterTask?.cancel()
        enterTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AudioTiming.enterHold))
            guard !Task.isCancelled else { return }
            guard self?.pendingNuggetID == nugget.id else { return }
            self?.start(nugget: nugget, language: language, directory: directory)
        }
    }

    func targetLost(nuggetID: String) {
        if pendingNuggetID == nuggetID {
            enterTask?.cancel()
            enterTask = nil
            pendingNuggetID = nil
            state = isPlaying ? .playing(currentPlaybackID ?? nuggetID) : .idle
        }
        guard activeNuggetID == nuggetID else { return }
        let exitedAt = Date()
        state = .exiting(exitedAt)
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AudioTiming.exitHold))
            guard !Task.isCancelled else { return }
            guard self?.activeNuggetID == nuggetID else { return }
            self?.stop(fadeDuration: AudioTiming.fadeOut)
        }
    }

    func replay(nugget: Nugget, language: String, directory: URL) {
        enterTask?.cancel()
        enterTask = nil
        exitTask?.cancel()
        exitTask = nil
        pendingNuggetID = nil
        start(nugget: nugget, language: language, directory: directory)
    }

    @discardableResult
    func playIntro(checkpoint: Checkpoint, language: String, directory: URL) -> Bool {
        let path = checkpoint.introAudio.v(language)
        guard !path.isEmpty else { return false }
        let url = directory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        enterTask?.cancel()
        enterTask = nil
        exitTask?.cancel()
        exitTask = nil
        pendingNuggetID = nil
        return startAudio(url: url, playbackID: "intro:\(checkpoint.id)", visitedNuggetID: nil)
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            isPlaying = player.play()
            if isPlaying, let currentPlaybackID { state = .playing(currentPlaybackID) }
        }
    }

    func seek(to position: Double) {
        guard let player, player.duration > 0 else { return }
        player.currentTime = min(max(position, 0), 1) * player.duration
        updateProgress(from: player)
    }

    func isCurrent(nuggetID: String) -> Bool {
        currentPlaybackID == nuggetID
    }

    func stop(fadeDuration: TimeInterval = 0) {
        enterTask?.cancel()
        enterTask = nil
        exitTask?.cancel()
        exitTask = nil
        fadeTask?.cancel()
        fadeTask = nil
        if fadeDuration > 0, let player, player.isPlaying {
            player.setVolume(0, fadeDuration: fadeDuration)
            fadeTask = Task { [weak self, weak player] in
                try? await Task.sleep(for: .seconds(fadeDuration))
                guard !Task.isCancelled, let self, let player, self.player === player else { return }
                self.finishStop()
            }
            return
        }
        finishStop()
    }

    private func finishStop() {
        fadeTask?.cancel()
        fadeTask = nil
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        elapsed = 0
        duration = 0
        state = .idle
        pendingNuggetID = nil
        activeNuggetID = nil
        currentPlaybackID = nil
    }

    private func start(nugget: Nugget, language: String, directory: URL) {
        guard pendingNuggetID == nil || pendingNuggetID == nugget.id else { return }
        let path = nugget.audio.v(language)
        let url = directory.appendingPathComponent(path)
        _ = startAudio(url: url, playbackID: nugget.id, visitedNuggetID: nugget.id)
    }

    @discardableResult
    private func startAudio(url: URL, playbackID: String, visitedNuggetID: String?) -> Bool {
        exitTask?.cancel()
        exitTask = nil
        fadeTask?.cancel()
        fadeTask = nil
        progressTimer?.invalidate()
        player?.stop()
        player = nil
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            player = next
            next.delegate = self
            next.volume = 0
            next.prepareToPlay()
            duration = next.duration
            elapsed = 0
            progress = 0
            guard next.play() else {
                player = nil
                state = .idle
                isPlaying = false
                return false
            }
            next.setVolume(1, fadeDuration: AudioTiming.fadeIn)
            state = .playing(playbackID)
            pendingNuggetID = nil
            activeNuggetID = visitedNuggetID
            currentPlaybackID = playbackID
            isPlaying = true
            if let visitedNuggetID { onStart?(visitedNuggetID) }
            startProgressTimer()
            return true
        } catch {
            player = nil
            state = .idle
            pendingNuggetID = nil
            activeNuggetID = nil
            currentPlaybackID = nil
            isPlaying = false
            return false
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.updateProgress(from: player)
            }
        }
    }

    private func updateProgress(from player: AVAudioPlayer) {
        elapsed = player.currentTime
        duration = player.duration
        progress = player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.stop()
        }
    }
}
