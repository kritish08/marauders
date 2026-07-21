@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AmbientAudioPlayer: ObservableObject {
    enum DuckReason: Hashable { case tourNarration, liveQuestion, checkpointSpeech }

    @Published private(set) var isAvailable = false
    @Published private(set) var isMuted = false
    @Published private(set) var isDucked = false

    private var player: AVAudioPlayer?
    private var duckReasons = Set<DuckReason>()
    private let normalVolume: Float = 0.18
    private let duckedVolume: Float = 0.08

    @discardableResult
    func start(installed: InstalledTour) -> Bool {
        stop()
        guard let url = audioURL(installed: installed) else { return false }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            next.volume = normalVolume
            next.prepareToPlay()
            guard next.play() else { return false }
            player = next
            isAvailable = true
            isMuted = false
            isDucked = false
            return true
        } catch {
            isAvailable = false
            return false
        }
    }

    private func audioURL(installed: InstalledTour) -> URL? {
        if let path = installed.package.monument.ambientTrack, !path.isEmpty {
            let packageURL = installed.fileURL(for: path)
            if FileManager.default.fileExists(atPath: packageURL.path) { return packageURL }
        }
        return Bundle.main.url(forResource: "default_ambient", withExtension: "m4a")
    }

    func setDucked(_ ducked: Bool, for reason: DuckReason) {
        if ducked { duckReasons.insert(reason) } else { duckReasons.remove(reason) }
        let shouldDuck = !duckReasons.isEmpty
        guard isAvailable, isDucked != shouldDuck else { return }
        isDucked = shouldDuck
        let target: Float = isMuted ? 0 : (shouldDuck ? duckedVolume : normalVolume)
        player?.setVolume(target, fadeDuration: shouldDuck ? 0.4 : 0.6)
    }

    func toggleMute() {
        guard isAvailable else { return }
        isMuted.toggle()
        let target: Float = isMuted ? 0 : (isDucked ? duckedVolume : normalVolume)
        player?.setVolume(target, fadeDuration: 0.3)
    }

    func stop() {
        player?.stop()
        player = nil
        isAvailable = false
        isDucked = false
        duckReasons.removeAll()
    }
}
