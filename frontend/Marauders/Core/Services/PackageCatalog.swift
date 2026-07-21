import Foundation

@MainActor
final class PackageCatalog: ObservableObject {
    struct HealthResponse: Decodable {
        let monuments: [String: Int]
    }

    @Published private(set) var monumentIDs: Set<String>?
    @Published private(set) var isRefreshing = false

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func isAvailable(_ packageID: String) -> Bool? {
        monumentIDs?.contains(packageID)
    }

    func isLocallyAvailable(_ packageID: String) -> Bool {
        if Bundle.main.url(forResource: packageID, withExtension: "zip") != nil { return true }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return false }
        let manifest = support.appendingPathComponent("TourPackages/\(packageID)/tour.json")
        return FileManager.default.fileExists(atPath: manifest.path)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let (data, response) = try await session.data(from: API.base.appendingPathComponent("health"))
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            monumentIDs = Set(try JSONDecoder().decode(HealthResponse.self, from: data).monuments.keys)
        } catch {
            // Preserve the last successful catalog during transient venue-network failures.
        }
    }
}
