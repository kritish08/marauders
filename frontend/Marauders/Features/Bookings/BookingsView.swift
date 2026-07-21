import SwiftUI

struct BookingsView: View {
    @EnvironmentObject private var packageCatalog: PackageCatalog

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surfaceLow.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header.oneTimeStaggeredReveal(0)
                        ForEach(MockData.bookings) { booking in
                            TourTicketCard(
                                booking: booking,
                                packageAvailable: packageCatalog.isAvailable(booking.packageID),
                                locallyAvailable: packageCatalog.isLocallyAvailable(booking.packageID)
                            )
                        }
                    }.padding(20)
                }
                .refreshable { await packageCatalog.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TourBooking.self) { TourPreparationView(booking: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR JOURNEYS").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Theme.gold)
                    Text("My Tours").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
                }
                Spacer()
                Image(systemName: "ticket.fill").foregroundStyle(Theme.primary).padding(12).background(Theme.surfaceHigh, in: Circle())
            }
            Text("Download once, then explore without a network connection.").foregroundStyle(Theme.mutedInk)
        }
    }
}

private struct TourTicketCard: View {
    let booking: TourBooking
    let packageAvailable: Bool?
    let locallyAvailable: Bool

    private var canPrepare: Bool { locallyAvailable || packageAvailable == true }

    var body: some View {
        VStack(spacing: 0) {
            Image(booking.imageName).resizable().scaledToFill().frame(height: 165).clipped()
                .allowsHitTesting(false).accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    Label(availabilityLabel, systemImage: availabilityIcon)
                        .font(.caption2.bold()).tracking(0.7).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7).background(availabilityColor.opacity(0.92), in: Capsule()).padding(14)
                }
            VStack(alignment: .leading, spacing: 12) {
                Text(booking.name).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Label(booking.city, systemImage: "mappin.and.ellipse")
                Divider().overlay(Theme.outline.opacity(0.6))
                NavigationLink(value: booking) {
                    HStack { Text(actionLabel).fontWeight(.semibold); Spacer(); Image(systemName: "arrow.down.to.line.compact") }
                        .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 48).background(canPrepare ? Theme.primary : Theme.outline, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canPrepare)
                .accessibilityIdentifier("viewTicket_\(booking.packageID.replacingOccurrences(of: "_", with: "-"))")
            }.font(.subheadline).foregroundStyle(Theme.mutedInk).padding(18)
        }
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(Theme.outline.opacity(0.7)) }
        .shadow(color: Theme.ink.opacity(0.07), radius: 12, y: 6)
    }

    private var availabilityLabel: LocalizedStringResource {
        if locallyAvailable { return "AVAILABLE OFFLINE" }
        return switch packageAvailable { case true: "PACKAGE AVAILABLE"; case false: "PACKAGE UNAVAILABLE"; case nil: "CHECKING PACKAGE" }
    }

    private var availabilityIcon: String {
        if locallyAvailable { return "checkmark.icloud.fill" }
        return switch packageAvailable { case true: "checkmark.icloud.fill"; case false: "icloud.slash.fill"; case nil: "arrow.triangle.2.circlepath.icloud.fill" }
    }

    private var availabilityColor: Color {
        if locallyAvailable { return Theme.teal }
        return switch packageAvailable { case true: Theme.teal; case false: Theme.mutedInk; case nil: Theme.gold }
    }

    private var actionLabel: LocalizedStringResource {
        if locallyAvailable { return "Prepare Tour" }
        return switch packageAvailable { case true: "Prepare Tour"; case false: "Tour Unavailable"; case nil: "Checking Availability" }
    }
}

struct TourPreparationView: View {
    let booking: TourBooking
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = PackageStore()
    @State private var installed: InstalledTour?
    @State private var selectedTourLanguage = AppLanguage.englishUK
    @State private var errorMessage: String?
    @State private var started = false

    var body: some View {
        Group {
            if started, let installed {
                TourContainerView(booking: booking, installed: installed, language: selectedTourLanguage.contentLanguageCode)
                    .transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 1.015)))
            } else {
                preparation
                    .transition(.opacity)
            }
        }
        .navigationTitle(started ? "" : booking.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(started ? .hidden : .visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if installed != nil, !started {
                startTourFooter
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.locale, Locale(identifier: selectedTourLanguage.localeIdentifier))
        .task { await prepare() }
    }

    private var preparation: some View {
        ZStack {
            Theme.surfaceLow.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    preparationHero
                    Group {
                        if let installed {
                            readyState(installed)
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else {
                            downloadState
                        }
                    }
                    .transition(Motion.subtleTransition(reduceMotion: reduceMotion))
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var preparationHero: some View {
        Image(booking.imageName)
            .resizable().scaledToFill()
            .frame(height: 220)
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, Theme.ink.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                Label("OFFLINE TOUR", systemImage: "arrow.down.circle.fill")
                    .font(.caption2.bold()).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.city.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(Theme.goldLight)
                    Text(booking.name).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.12), radius: 16, y: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var downloadState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: store.downloadProgress >= 0.65 ? "shippingbox.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48)
                    .background(Theme.goldLight.opacity(0.35), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(downloadPhaseLabel)
                        .font(.headline).foregroundStyle(Theme.ink)
                    Text("Stories, maps and audio will be available without a connection.")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
            }
            VStack(spacing: 8) {
                ProgressView(value: store.downloadProgress)
                    .tint(Theme.primary)
                    .scaleEffect(y: 1.5)
                HStack {
                    Text(downloadStatusLabel)
                    Spacer()
                    Text("\(Int(store.downloadProgress * 100))%")
                        .monospacedDigit().fontWeight(.bold)
                }
                .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Label("You can leave this screen open while we finish.", systemImage: "lock.shield.fill")
                .font(.caption).foregroundStyle(Theme.teal)
        }
        .padding(20)
        .heritageCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing offline tour, \(Int(store.downloadProgress * 100)) percent")
    }

    private var downloadPhaseLabel: LocalizedStringResource {
        store.downloadProgress >= 0.65 ? "Installing your guide" : "Preparing offline tour"
    }

    private var downloadStatusLabel: LocalizedStringResource {
        store.isDownloading ? "Downloading package…" : "Checking package…"
    }

    private func readyState(_ installed: InstalledTour) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.headline.bold()).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Theme.teal, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tour ready offline").font(.title3.bold()).foregroundStyle(Theme.ink)
                    Text("Downloaded and ready to explore").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer()
            }
            Text(installed.package.monument.overview.v(selectedTourLanguage.contentLanguageCode))
                .font(.subheadline).foregroundStyle(Theme.mutedInk).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            languageMenu
        }
        .padding(18)
        .heritageCard()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30)).foregroundStyle(Theme.primary)
                .frame(width: 58, height: 58).background(Theme.primary.opacity(0.1), in: Circle())
            Text("Package unavailable").font(.title3.bold()).foregroundStyle(Theme.ink)
            Text(message).font(.subheadline).foregroundStyle(Theme.mutedInk).multilineTextAlignment(.center)
            Button("Retry Download") { Task { await prepare(forceRemote: true) } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .heritageCard()
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selectedTourLanguage = language
                } label: {
                    if language == selectedTourLanguage {
                        Label {
                            Text(verbatim: language.title)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: language.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GUIDE LANGUAGE")
                        .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(Theme.mutedInk)
                    Text(verbatim: selectedTourLanguage.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.bold()).foregroundStyle(Theme.mutedInk)
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.outline.opacity(0.7)) }
        }
        .buttonStyle(SubtlePressButtonStyle())
        .accessibilityLabel("Guide language, \(selectedTourLanguage.title)")
        .accessibilityHint("Opens the guide language menu.")
        .accessibilityIdentifier("languagePicker")
    }

    private var startTourFooter: some View {
        VStack(spacing: 9) {
            Label("Please use headphones for a better experience.", systemImage: "headphones")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start Tour") { startTour() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("startTourButton")
        }
        .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(Theme.outline.opacity(0.55)) }
    }

    private func prepare(forceRemote: Bool = false) async {
        errorMessage = nil
        do {
            let prepared = try await store.prepare(monumentID: booking.packageID, preferBundled: !forceRemote)
            withAnimation(Motion.change(reduceMotion: reduceMotion)) {
                installed = prepared
                selectedTourLanguage = session.appLanguage
            }
        } catch {
            withAnimation(Motion.change(reduceMotion: reduceMotion)) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startTour() {
        guard installed != nil else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) {
            started = true
        }
    }
}
