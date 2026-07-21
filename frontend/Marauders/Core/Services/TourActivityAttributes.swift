import ActivityKit
import Foundation

// KEEP IN SYNC with MaraudersWidgets/TourActivityAttributes.swift — ActivityKit matches
// the app's and extension's attribute payloads by type name and coding keys.
struct TourActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var chapterName: String
        var completedChapters: Int
        var totalChapters: Int
        var isNarrating: Bool
    }

    var monumentName: String
}
