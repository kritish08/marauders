import Foundation

enum API {
    static let azureBase = URL(string: "https://marauders-backend.azurewebsites.net")!
    static let base = azureBase

    static var appKey: String {
        ProcessInfo.processInfo.environment["MARAUDERS_APP_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "MaraudersAppKey") as? String
            ?? ""
    }
}
