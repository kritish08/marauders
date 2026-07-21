import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case englishUK
    case hindi
    case french
    case spanish

    var id: Self { self }

    var title: String {
        switch self {
        case .englishUK: "English (UK)"
        case .hindi: "हिन्दी"
        case .french: "Français"
        case .spanish: "Español"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .englishUK: "en_GB"
        case .hindi: "hi_IN"
        case .french: "fr_FR"
        case .spanish: "es_ES"
        }
    }

    var contentLanguageCode: String {
        switch self {
        case .englishUK: "en"
        case .hindi: "hi"
        case .french: "fr"
        case .spanish: "es"
        }
    }
}

enum DisabilityStatus: String, CaseIterable, Identifiable {
    case no = "No"
    case yes = "Yes"
    case preferNotToSay = "Prefer not to say"

    var id: Self { self }
}

@MainActor
@Observable
final class AppSession {
    var isAuthenticated = false
    var userPhone = ""
    var userName: String
    var email: String
    var gender: String
    var dateOfBirth: Date
    var disabilityStatus: DisabilityStatus
    var accessibilityNotes: String
    var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }
    var prefersLargeText: Bool {
        didSet { defaults.set(prefersLargeText, forKey: Keys.prefersLargeText) }
    }
    var prefersHighContrast: Bool {
        didSet { defaults.set(prefersHighContrast, forKey: Keys.prefersHighContrast) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userName = defaults.string(forKey: Keys.userName) ?? "Swift Dzire LXI"
        email = defaults.string(forKey: Keys.email) ?? ""
        gender = defaults.string(forKey: Keys.gender) ?? "Prefer not to say"
        dateOfBirth = defaults.object(forKey: Keys.dateOfBirth) as? Date ?? Date(timeIntervalSince1970: 946_684_800)
        disabilityStatus = DisabilityStatus(rawValue: defaults.string(forKey: Keys.disabilityStatus) ?? "") ?? .preferNotToSay
        accessibilityNotes = defaults.string(forKey: Keys.accessibilityNotes) ?? ""
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .englishUK
        prefersLargeText = defaults.bool(forKey: Keys.prefersLargeText)
        prefersHighContrast = defaults.bool(forKey: Keys.prefersHighContrast)
    }

    func signIn(phone: String) {
        userPhone = phone
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        userPhone = ""
    }

    func updateProfile(name: String, email: String, gender: String, dateOfBirth: Date, disabilityStatus: DisabilityStatus, accessibilityNotes: String) {
        userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gender = gender
        self.dateOfBirth = dateOfBirth
        self.disabilityStatus = disabilityStatus
        self.accessibilityNotes = accessibilityNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        defaults.set(userName, forKey: Keys.userName)
        defaults.set(self.email, forKey: Keys.email)
        defaults.set(self.gender, forKey: Keys.gender)
        defaults.set(self.dateOfBirth, forKey: Keys.dateOfBirth)
        defaults.set(self.disabilityStatus.rawValue, forKey: Keys.disabilityStatus)
        defaults.set(self.accessibilityNotes, forKey: Keys.accessibilityNotes)
    }

    private enum Keys {
        static let userName = "profile.userName"
        static let email = "profile.email"
        static let gender = "profile.gender"
        static let dateOfBirth = "profile.dateOfBirth"
        static let disabilityStatus = "profile.disabilityStatus"
        static let accessibilityNotes = "profile.accessibilityNotes"
        static let appLanguage = "preferences.appLanguage"
        static let prefersLargeText = "preferences.prefersLargeText"
        static let prefersHighContrast = "preferences.prefersHighContrast"
    }
}
