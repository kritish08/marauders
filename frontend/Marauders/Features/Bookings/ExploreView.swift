import CoreLocation
import SwiftUI

struct ExploreView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var packageCatalog: PackageCatalog
    @StateObject private var locationService = LocationService()
    @AppStorage("explore.manualCity") private var manualCity = ""
    @State private var detectedCity = "Finding your location..."
    @State private var selectedCategory = DiscoveryCategory.all

    private let cityOptions = ["New Delhi", "Agra", "Gurugram", "Mumbai", "Amritsar"]

    private var displayedCity: String {
        if !manualCity.isEmpty { return manualCity }
        if locationService.authorization == .denied || locationService.authorization == .restricted {
            return "Choose your city"
        }
        return detectedCity
    }

    private var visibleItems: [DiscoveryItem] {
        let items = selectedCategory == .all ? DiscoveryItem.samples : DiscoveryItem.samples.filter { $0.category == selectedCategory }
        let city = manualCity.isEmpty ? detectedCity : manualCity
        guard !city.contains("location"), !city.contains("Finding"), !city.contains("Choose") else { return items }
        let localItems = items.filter { citiesMatch($0.city, city) }
        return localItems.isEmpty && manualCity.isEmpty ? items : localItems
    }

    private var featuredItems: [DiscoveryItem] {
        visibleItems.filter { $0.category != .event }
    }

    private var nearbyEvents: [DiscoveryItem] {
        visibleItems.filter { $0.category == .event }
    }

    private var featuredColumnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surfaceLow.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        locationHeader.oneTimeStaggeredReveal(0)
                        introduction.oneTimeStaggeredReveal(1)
                        categoryPicker.oneTimeStaggeredReveal(2)
                        discoveryContent
                            .animation(Motion.change(reduceMotion: reduceMotion), value: selectedCategory)
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await packageCatalog.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if manualCity.isEmpty { locationService.start() }
            }
            .onDisappear { locationService.stop() }
            .onChange(of: locationService.location) { _, _ in
                guard manualCity.isEmpty, detectedCity == "Finding your location..." else { return }
                Task {
                    detectedCity = await locationService.currentPlaceName() ?? "Current location"
                }
            }
        }
    }

    private var locationHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.primary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR LOCATION").font(.caption2.bold()).tracking(1).foregroundStyle(Theme.gold)
                Menu {
                    Button {
                        manualCity = ""
                        detectedCity = "Finding your location..."
                        locationService.start()
                    } label: {
                        Label("Use current location", systemImage: "location.fill")
                    }
                    Divider()
                    ForEach(cityOptions, id: \.self) { city in
                        Button(city) { manualCity = city }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(displayedCity).font(.headline).foregroundStyle(Theme.ink)
                            .contentTransition(.opacity)
                            .animation(Motion.change(reduceMotion: reduceMotion), value: displayedCity)
                        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(Theme.primary)
                    }
                }
                .accessibilityLabel("Selected location, \(displayedCity)")
                .accessibilityHint("Opens city choices")
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GO SOMEWHERE REMARKABLE")
                .font(.caption.bold()).tracking(1.4).foregroundStyle(Theme.gold)
            Text("Culture and Stories Nearby")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Discover monuments, museums and events, then continue to District to book.")
                .foregroundStyle(Theme.mutedInk)
        }
        .padding(.horizontal, 20)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(DiscoveryCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(LocalizedStringKey(category.title), systemImage: category.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCategory == category ? .white : Theme.primary)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(selectedCategory == category ? Theme.primary : Theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(Theme.outline.opacity(selectedCategory == category ? 0 : 0.7)) }
                            .animation(reduceMotion ? nil : Motion.quick, value: selectedCategory)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if visibleItems.isEmpty {
            ContentUnavailableView(
                "Nothing listed in \(displayedCity) yet",
                systemImage: "mappin.slash",
                description: Text("Choose another city or use your current location to see popular experiences.")
            )
            .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 30)
        } else {
            if !featuredItems.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    sectionTitle("Tickets worth the trip", detail: "Monuments and museums")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(featuredItems) { item in
                                FeaturedTicketCard(item: item, book: openDistrict)
                                    .containerRelativeFrame(.horizontal, count: featuredColumnCount, span: 1, spacing: 14)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 20)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }

            if !nearbyEvents.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    sectionTitle("Happening nearby", detail: "Events around \(displayedCity)")
                    ForEach(nearbyEvents) { item in
                        NearbyEventCard(item: item, book: openDistrict)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
            Text(detail).font(.subheadline).foregroundStyle(Theme.mutedInk)
        }
        .padding(.horizontal, 20)
    }

    private func openDistrict() {
        guard let districtURL = URL(string: "https://www.district.in/") else { return }
        openURL(districtURL)
    }

    private func citiesMatch(_ listingCity: String, _ selectedCity: String) -> Bool {
        let listing = listingCity.lowercased()
        let selected = selectedCity.lowercased()
        if listing.contains("delhi"), selected.contains("delhi") { return true }
        return listing.contains(selected) || selected.contains(listing)
    }
}

private struct FeaturedTicketCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: DiscoveryItem
    let book: () -> Void

    private var contentHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 250 : 176
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            discoveryArtwork(item, height: 116)
            VStack(alignment: .leading, spacing: 7) {
                Label(LocalizedStringKey(item.category.title), systemImage: item.category.icon)
                    .font(.caption2.bold()).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.gold)
                Text(item.name)
                    .font(.headline).foregroundStyle(Theme.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 40, alignment: .topLeading)
                Label(item.city, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
                Text(item.detail).font(.caption.weight(.semibold)).foregroundStyle(Theme.teal)
                Spacer(minLength: 4)
                districtButton(book)
            }
            .padding(12)
            .frame(height: contentHeight, alignment: .topLeading)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.outline.opacity(0.65)) }
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 4)
    }
}

private struct NearbyEventCard: View {
    let item: DiscoveryItem
    let book: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            discoveryArtwork(item, width: 96, height: 112)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.name).font(.headline).foregroundStyle(Theme.ink)
                Text(item.detail).font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                Label(item.city, systemImage: "location")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                districtButton(book)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.outline.opacity(0.55)) }
    }
}

@ViewBuilder
private func discoveryArtwork(_ item: DiscoveryItem, width: CGFloat? = nil, height: CGFloat) -> some View {
    if let imageName = item.imageName {
        Image(imageName)
            .resizable().scaledToFill()
            .frame(width: width, height: height).clipped()
            .accessibilityHidden(true)
    } else {
        ZStack {
            LinearGradient(colors: [Theme.primary, Theme.gold], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.category.artworkIcon)
                .font(.system(size: width == nil ? 56 : 34, weight: .light))
                .foregroundStyle(Theme.goldLight)
        }
        .frame(width: width, height: height).clipped()
        .accessibilityHidden(true)
    }
}

private func districtButton(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label("Open District", systemImage: "arrow.up.right.square.fill")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.primary, in: Capsule())
    }
    .accessibilityHint("Opens District to book tickets")
}

private enum DiscoveryCategory: String, CaseIterable, Identifiable {
    case all, monument, museum, event

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .all: "sparkles"
        case .monument: "building.columns.fill"
        case .museum: "building.2.fill"
        case .event: "calendar.badge.clock"
        }
    }
    var artworkIcon: String {
        switch self {
        case .all: "sparkles"
        case .monument: "building.columns"
        case .museum: "photo.artframe"
        case .event: "music.note.list"
        }
    }
}

private struct DiscoveryItem: Identifiable {
    let id: String
    let name: String
    let city: String
    let detail: String
    let category: DiscoveryCategory
    let imageName: String?

    static let samples: [DiscoveryItem] = [
        DiscoveryItem(id: "taj", name: "Taj Mahal", city: "Agra", detail: "Entry from Rs 50", category: .monument, imageName: "TajMahalMap"),
        DiscoveryItem(id: "war-memorial", name: "National War Memorial", city: "New Delhi", detail: "Free entry", category: .monument, imageName: "WarMemorialMap"),
        DiscoveryItem(id: "humayun", name: "Humayun's Tomb", city: "New Delhi", detail: "Entry from Rs 40", category: .monument, imageName: nil),
        DiscoveryItem(id: "national-museum", name: "National Museum", city: "New Delhi", detail: "Entry from Rs 20", category: .museum, imageName: nil),
        DiscoveryItem(id: "partition-museum", name: "Partition Museum", city: "Amritsar", detail: "Entry from Rs 10", category: .museum, imageName: nil),
        DiscoveryItem(id: "illusion", name: "Museum of Illusions", city: "New Delhi", detail: "Tickets available", category: .museum, imageName: nil),
        DiscoveryItem(id: "heritage-walk", name: "Old Agra Heritage Walk", city: "Agra", detail: "Today - 5:30 PM", category: .event, imageName: "TajMahalMap"),
        DiscoveryItem(id: "art-night", name: "Delhi Art After Dark", city: "New Delhi", detail: "Sat - 7:00 PM", category: .event, imageName: nil),
        DiscoveryItem(id: "cyberhub-live", name: "CyberHub Live", city: "Gurugram", detail: "Fri - 8:00 PM", category: .event, imageName: "ZomatoFarmMap"),
        DiscoveryItem(id: "museum-night", name: "Mumbai Museum Night", city: "Mumbai", detail: "Sun - 6:00 PM", category: .event, imageName: nil)
    ]
}
