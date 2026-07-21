import Foundation

@MainActor
final class TourSession: ObservableObject {
    let installed: InstalledTour
    @Published var language: String
    @Published var currentCheckpointID: String
    @Published var activeNuggetID: String?

    init(installed: InstalledTour, language: String) {
        self.installed = installed
        self.language = language
        self.currentCheckpointID = installed.package.checkpoints.sorted { $0.order < $1.order }.first?.id ?? ""
    }

    var currentCheckpoint: Checkpoint? {
        installed.package.checkpoints.first { $0.id == currentCheckpointID }
    }

    var activeNugget: Nugget? {
        guard let activeNuggetID else { return nil }
        return installed.package.checkpoints.flatMap(\.nuggets).first { $0.id == activeNuggetID }
    }

    func select(checkpoint: Checkpoint, nugget: Nugget? = nil) {
        if nugget == nil, checkpoint.id != currentCheckpointID { activeNuggetID = nil }
        currentCheckpointID = checkpoint.id
        if let nugget { activeNuggetID = nugget.id }
    }

    func checkpoint(containing nuggetID: String) -> Checkpoint? {
        installed.package.checkpoints.first { checkpoint in checkpoint.nuggets.contains { $0.id == nuggetID } }
    }
}
