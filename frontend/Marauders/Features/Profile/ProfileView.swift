import SwiftUI

struct ProfileView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            List {
                profileHeader

                Section("PREFERENCES") {
                    NavigationLink {
                        AccountDetailsView()
                    } label: {
                        settingsRow("Account details", subtitle: "Name, email, gender and support needs", icon: "person.text.rectangle")
                    }

                    NavigationLink {
                        LanguagePreferencesView()
                    } label: {
                        settingsRow("App language", subtitle: session.appLanguage.title, icon: "globe")
                    }

                    NavigationLink {
                        DownloadedJourneysView()
                    } label: {
                        settingsRow("Downloaded journeys", subtitle: "Manage offline tour packages", icon: "arrow.down.circle")
                    }

                    NavigationLink {
                        AccessibilityPreferencesView()
                    } label: {
                        settingsRow("Accessibility", subtitle: "Text size and visual contrast", icon: "accessibility")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { session.signOut() }
                        .accessibilityIdentifier("signOutButton")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceLow)
            .navigationTitle("Profile")
        }
    }

    private var profileHeader: some View {
        Section {
            HStack(spacing: 16) {
                LionHouseCrestAvatar()
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.userName).font(.headline)
                    Text(session.email.isEmpty ? "Add account details" : session.email)
                        .font(.subheadline).foregroundStyle(Theme.mutedInk)
                    if !session.userPhone.isEmpty {
                        Text(session.userPhone).font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func settingsRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.primary)
                .frame(width: 34, height: 34)
                .background(Theme.goldLight.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.body.weight(.semibold))
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct LionHouseCrestAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.ink, Theme.primary], startPoint: .topLeading, endPoint: .bottomTrailing))
            HouseShield()
                .fill(LinearGradient(colors: [Color(hex: 0xA43B3F), Theme.primary], startPoint: .top, endPoint: .bottom))
                .frame(width: 45, height: 52)
                .overlay { HouseShield().stroke(Theme.goldLight, lineWidth: 2).frame(width: 45, height: 52) }
            VStack(spacing: -1) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("G")
                    .font(.system(size: 25, weight: .black, design: .serif))
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Theme.goldLight)
        }
        .frame(width: 68, height: 68)
        .overlay { Circle().stroke(Theme.gold, lineWidth: 2.5) }
        .shadow(color: Theme.primary.opacity(0.28), radius: 7, y: 4)
        .accessibilityLabel("Gryffindor-inspired lion house crest avatar")
    }
}

private struct HouseShield: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.midY + rect.height * 0.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.9)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.2),
            control: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.9)
        )
        path.closeSubpath()
        return path
    }
}

private struct AccountDetailsView: View {
    @Environment(AppSession.self) private var session
    @State private var userName = ""
    @State private var email = ""
    @State private var gender = "Prefer not to say"
    @State private var dateOfBirth = Date(timeIntervalSince1970: 946_684_800)
    @State private var disabilityStatus = DisabilityStatus.preferNotToSay
    @State private var accessibilityNotes = ""
    @State private var showSavedConfirmation = false

    private let genders = ["Woman", "Man", "Non-binary", "Prefer not to say"]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    LionHouseCrestAvatar()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName.isEmpty ? session.userName : userName).font(.headline)
                        Text("Your private account profile").font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("PERSONAL INFORMATION") {
                TextField("User name", text: $userName)
                    .textContentType(.name)
                    .accessibilityIdentifier("profileUserName")
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .accessibilityIdentifier("profileEmail")
                Picker("Gender", selection: $gender) {
                    ForEach(genders, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                }
                DatePicker("Date of birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("profileDateOfBirth")
            }

            Section("ACCESSIBILITY INFORMATION") {
                Picker("Disability status", selection: $disabilityStatus) {
                    ForEach(DisabilityStatus.allCases) { status in
                        Text(LocalizedStringKey(status.rawValue)).tag(status)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility needs or comments").font(.subheadline)
                    TextEditor(text: $accessibilityNotes)
                        .frame(minHeight: 100)
                        .padding(6)
                        .background(Theme.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("accessibilityNotes")
                    Text("Optional. This information is stored only on this device.")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
            }

            Section {
                Button("Update Profile") { saveProfile() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("updateProfileButton")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surfaceLow)
        .navigationTitle("Account Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadProfile)
        .alert("Profile updated", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your account details and accessibility information were saved on this device.")
        }
    }

    private func loadProfile() {
        userName = session.userName
        email = session.email
        gender = session.gender
        dateOfBirth = session.dateOfBirth
        disabilityStatus = session.disabilityStatus
        accessibilityNotes = session.accessibilityNotes
    }

    private func saveProfile() {
        session.updateProfile(
            name: userName,
            email: email,
            gender: gender,
            dateOfBirth: dateOfBirth,
            disabilityStatus: disabilityStatus,
            accessibilityNotes: accessibilityNotes
        )
        showSavedConfirmation = true
    }
}

private struct LanguagePreferencesView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session

        Form {
            Section("APPLICATION LANGUAGE") {
                Picker("Language", selection: $session.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Label("Changes apply immediately", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.teal)
                Text("Your selected language applies across the app. Monument content falls back to English when a translation is unavailable.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surfaceLow)
        .navigationTitle("App Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccessibilityPreferencesView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session

        Form {
            Section("READING") {
                Toggle("Larger text", isOn: $session.prefersLargeText)
                Text("Increases text throughout the app to an accessibility reading size.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Section("VISIBILITY") {
                Toggle("Higher contrast", isOn: $session.prefersHighContrast)
                Text("Strengthens visual contrast across screens, controls and tour content.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Section {
                Label("Settings apply immediately and are saved automatically.", systemImage: "accessibility")
                    .font(.subheadline).foregroundStyle(Theme.teal)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surfaceLow)
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DownloadedJourneysView: View {
    @StateObject private var packageStore = PackageStore()
    @State private var downloadedBookings: [TourBooking] = []

    var body: some View {
        List {
            if downloadedBookings.isEmpty {
                ContentUnavailableView(
                    "No downloaded journeys",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded tour packages will appear here for offline access.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("AVAILABLE OFFLINE") {
                    ForEach(downloadedBookings) { booking in
                        HStack(spacing: 12) {
                            Image(booking.imageName)
                                .resizable().scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(booking.name).font(.headline)
                                Text(booking.city).font(.caption).foregroundStyle(Theme.mutedInk)
                            }
                            Spacer()
                            Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.teal)
                                .accessibilityLabel("Available offline")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surfaceLow)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshDownloads)
    }

    private func refreshDownloads() {
        downloadedBookings = MockData.bookings.filter { booking in
            (try? packageStore.installedTour(monumentID: booking.packageID)) != nil
        }
    }
}
