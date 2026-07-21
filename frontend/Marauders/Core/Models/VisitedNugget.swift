import Foundation
import SwiftData

@Model
final class VisitedNugget {
    var id: String
    var checkpointId: String
    var monumentId: String
    var timestamp: Date

    init(id: String, checkpointId: String, monumentId: String, timestamp: Date = .now) {
        self.id = id
        self.checkpointId = checkpointId
        self.monumentId = monumentId
        self.timestamp = timestamp
    }
}
