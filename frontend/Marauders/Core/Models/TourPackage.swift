import Foundation

typealias LangMap = [String: String]

extension LangMap {
    func v(_ lang: String) -> String { self[lang] ?? self["en"] ?? "" }
    func mediaPath(_ lang: String) -> String { self[lang] ?? self["en"] ?? values.first ?? "" }
}

struct TourPackage: Codable {
    let schemaVersion: Int
    let monument: Monument
    let routes: Routes?
    let checkpoints: [Checkpoint]
}

struct Monument: Codable {
    let id: String
    let name: LangMap
    let languages: [String]
    let overview: LangMap
    let ambientTrack: String?
}

struct Routes: Codable { let monument: Route?; let venue: Route? }
struct Route: Codable { let start: String; let end: String }

struct Checkpoint: Codable, Identifiable {
    let id: String
    let order: Int
    let name: LangMap
    let mapPosition: MapPosition
    let gps: GPS?
    let venue: Bool
    let intro: LangMap
    let introAudio: LangMap
    let nuggets: [Nugget]
}

struct MapPosition: Codable { let x: Double; let y: Double }
struct GPS: Codable { let lat: Double; let lng: Double; let radius: Double }

struct Nugget: Codable, Identifiable {
    let id: String
    let title: LangMap
    let targetImageId: String
    let targetImageIds: [String]
    let exclusive: Bool
    let images: [String]
    let text: LangMap
    let audio: LangMap
    let targetPhysicalWidthM: Double?

    init(
        id: String,
        title: LangMap,
        targetImageId: String,
        targetImageIds: [String] = [],
        exclusive: Bool,
        images: [String] = [],
        text: LangMap,
        audio: LangMap,
        targetPhysicalWidthM: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.targetImageId = targetImageId
        self.targetImageIds = targetImageIds
        self.exclusive = exclusive
        self.images = images
        self.text = text
        self.audio = audio
        self.targetPhysicalWidthM = targetPhysicalWidthM
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, targetImageId, targetImageIds, exclusive, images, text, audio, targetPhysicalWidthM
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(LangMap.self, forKey: .title)
        targetImageId = try values.decode(String.self, forKey: .targetImageId)
        targetImageIds = try values.decodeIfPresent([String].self, forKey: .targetImageIds) ?? []
        exclusive = try values.decode(Bool.self, forKey: .exclusive)
        images = try values.decodeIfPresent([String].self, forKey: .images) ?? []
        text = try values.decode(LangMap.self, forKey: .text)
        audio = try values.decode(LangMap.self, forKey: .audio)
        targetPhysicalWidthM = try values.decodeIfPresent(Double.self, forKey: .targetPhysicalWidthM)
    }

    var effectiveTargetImageIds: [String] {
        var seen = Set<String>()
        return ([targetImageId] + targetImageIds).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct InstalledTour {
    let package: TourPackage
    let directory: URL

    func fileURL(for relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    func targetURL(for nugget: Nugget) -> URL {
        targetURL(forID: nugget.targetImageId)
    }

    func targetURL(forID targetID: String) -> URL {
        directory.appendingPathComponent("targets/\(targetID).jpg")
    }

    func displayURLs(for nugget: Nugget) -> [URL] {
        let gallery = nugget.images.map(fileURL(for:))
        return gallery.isEmpty ? [targetURL(for: nugget)] : gallery
    }
}
