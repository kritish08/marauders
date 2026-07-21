import Foundation
import ZIPFoundation

@MainActor
final class PackageStore: ObservableObject {
    enum PackageError: LocalizedError {
        case missingBundledPackage(String)
        case invalidResponse
        case invalidPackage(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledPackage(let id): "No bundled package is available for \(id). Connect to download it."
            case .invalidResponse: "The tour package server returned an invalid response."
            case .invalidPackage(let reason): "The tour package is incomplete: \(reason)"
            }
        }
    }

    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isDownloading = false

    private let fileManager: FileManager
    private let session: URLSession
    private let markerName = ".package-source"

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func installedTour(monumentID: String) throws -> InstalledTour? {
        let directory = try packageDirectory(monumentID: monumentID)
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("tour.json").path) else { return nil }
        return try decodeAndValidate(directory: directory, expectedMonumentID: monumentID)
    }

    func prepare(monumentID: String, preferBundled: Bool = true) async throws -> InstalledTour {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        if preferBundled, let bundled = Bundle.main.url(forResource: monumentID, withExtension: "zip") {
            let fingerprint = try archiveFingerprint(bundled)
            if let installed = try? installedTour(monumentID: monumentID),
               try installedFingerprint(monumentID: monumentID) == fingerprint {
                downloadProgress = 1
                return installed
            }
            downloadProgress = 0.35
            return try install(archive: bundled, monumentID: monumentID, fingerprint: fingerprint)
        }

        if preferBundled, let installed = try? installedTour(monumentID: monumentID) {
            downloadProgress = 1
            return installed
        }

        let archiveURL = try await download(monumentID: monumentID)
        defer { try? fileManager.removeItem(at: archiveURL) }
        downloadProgress = 0.65
        return try install(
            archive: archiveURL,
            monumentID: monumentID,
            fingerprint: "remote-\(UUID().uuidString)"
        )
    }

    func remove(monumentID: String) throws {
        let directory = try packageDirectory(monumentID: monumentID)
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    private func download(monumentID: String) async throws -> URL {
        let url = API.base.appendingPathComponent("packages/\(monumentID).zip")
        let (temporaryURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw PackageError.invalidResponse }
        let destination = fileManager.temporaryDirectory.appendingPathComponent("\(monumentID)-\(UUID().uuidString).zip")
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func install(archive: URL, monumentID: String, fingerprint: String) throws -> InstalledTour {
        let root = try packageRoot()
        let destination = root.appendingPathComponent(monumentID, isDirectory: true)
        let staging = root.appendingPathComponent(".\(monumentID)-staging-\(UUID().uuidString)", isDirectory: true)
        let backup = root.appendingPathComponent(".\(monumentID)-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            try fileManager.unzipItem(at: archive, to: staging)
            let validated = try decodeAndValidate(directory: staging, expectedMonumentID: monumentID)
            try Data(fingerprint.utf8).write(to: staging.appendingPathComponent(markerName), options: .atomic)

            if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: backup) }
            do {
                try fileManager.moveItem(at: staging, to: destination)
                try? fileManager.removeItem(at: backup)
            } catch {
                if fileManager.fileExists(atPath: backup.path) { try? fileManager.moveItem(at: backup, to: destination) }
                throw error
            }
            downloadProgress = 1
            return InstalledTour(package: validated.package, directory: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func packageRoot() throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TourPackages", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func packageDirectory(monumentID: String) throws -> URL {
        try packageRoot().appendingPathComponent(monumentID, isDirectory: true)
    }

    private func archiveFingerprint(_ archive: URL) throws -> String {
        let values = try archive.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "bundle-\(values.fileSize ?? 0)-\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private func installedFingerprint(monumentID: String) throws -> String? {
        let marker = try packageDirectory(monumentID: monumentID).appendingPathComponent(markerName)
        guard fileManager.fileExists(atPath: marker.path) else { return nil }
        return String(data: try Data(contentsOf: marker), encoding: .utf8)
    }

    func decodeAndValidate(directory: URL, expectedMonumentID: String? = nil) throws -> InstalledTour {
        let data = try Data(contentsOf: directory.appendingPathComponent("tour.json"))
        let tourPackage = try JSONDecoder().decode(TourPackage.self, from: data)
        guard tourPackage.schemaVersion == 1 else { throw PackageError.invalidPackage("unsupported schema version") }
        if let expectedMonumentID, tourPackage.monument.id != expectedMonumentID {
            throw PackageError.invalidPackage("package monument does not match \(expectedMonumentID)")
        }

        let checkpoints = tourPackage.checkpoints.compactMap { checkpoint -> Checkpoint? in
            let introAudio = checkpoint.introAudio.filter { safeFileExists($0.value, in: directory) }
            let nuggets = checkpoint.nuggets.compactMap { nugget -> Nugget? in
                let audio = nugget.audio.filter { safeFileExists($0.value, in: directory) }
                guard !audio.isEmpty else { return nil }
                let images = nugget.images.filter { safeFileExists($0, extension: "webp", in: directory) }
                let targetID = safePathComponent(nugget.targetImageId) ? nugget.targetImageId : ""
                var seenTargetIDs = Set([targetID])
                let targetIDs = nugget.targetImageIds.filter {
                    safePathComponent($0)
                        && safeFileExists("targets/\($0).jpg", extension: "jpg", in: directory)
                        && seenTargetIDs.insert($0).inserted
                }
                return Nugget(
                    id: nugget.id,
                    title: nugget.title,
                    targetImageId: targetID,
                    targetImageIds: targetIDs,
                    exclusive: nugget.exclusive,
                    images: images,
                    text: nugget.text,
                    audio: audio,
                    targetPhysicalWidthM: nugget.targetPhysicalWidthM
                )
            }
            guard !nuggets.isEmpty else { return nil }
            return Checkpoint(
                id: checkpoint.id,
                order: checkpoint.order,
                name: checkpoint.name,
                mapPosition: checkpoint.mapPosition,
                gps: checkpoint.gps,
                venue: checkpoint.venue,
                intro: checkpoint.intro,
                introAudio: introAudio,
                nuggets: nuggets
            )
        }

        guard !checkpoints.isEmpty else { throw PackageError.invalidPackage("no playable checkpoints") }
        let survivingIDs = Set(checkpoints.map(\.id))
        let routes = sanitizedRoutes(tourPackage.routes, survivingIDs: survivingIDs)
        let sanitized = TourPackage(
            schemaVersion: tourPackage.schemaVersion,
            monument: tourPackage.monument,
            routes: routes,
            checkpoints: checkpoints
        )
        return InstalledTour(package: sanitized, directory: directory)
    }

    private func safeFileExists(_ relativePath: String, extension requiredExtension: String? = nil, in directory: URL) -> Bool {
        guard safeRelativePath(relativePath) else { return false }
        let candidate = directory.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard candidate.path.hasPrefix(root) else { return false }
        if let requiredExtension, candidate.pathExtension.lowercased() != requiredExtension { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func safeRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private func safePathComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && value != "." && value != ".."
    }

    private func sanitizedRoutes(_ routes: Routes?, survivingIDs: Set<String>) -> Routes? {
        guard let routes else { return nil }
        func keep(_ route: Route?) -> Route? {
            guard let route, survivingIDs.contains(route.start), survivingIDs.contains(route.end) else { return nil }
            return route
        }
        let sanitized = Routes(monument: keep(routes.monument), venue: keep(routes.venue))
        return sanitized.monument == nil && sanitized.venue == nil ? nil : sanitized
    }
}
