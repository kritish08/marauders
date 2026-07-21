import Foundation
import Testing
@testable import Marauders

struct MaraudersTests {
    @Test @MainActor func bundledPackageInstallsAndValidates() async throws {
        let store = PackageStore()
        try? store.remove(monumentID: "taj_mahal")
        let installed = try await store.prepare(monumentID: "taj_mahal", preferBundled: true)

        #expect(installed.package.schemaVersion == 1)
        #expect(installed.package.monument.id == "taj_mahal")
        #expect(installed.package.checkpoints.count == 4)
        #expect(installed.package.checkpoints.allSatisfy { !$0.venue })
        #expect(installed.package.routes?.venue == nil)
        #expect(installed.package.monument.languages.contains("en"))
        #expect(installed.package.monument.languages.contains("hi"))
        #expect(installed.package.monument.languages.contains("fr"))
        #expect(installed.package.monument.languages.contains("es"))
        #expect(installed.package.checkpoints.flatMap(\.nuggets).flatMap(\.images).count == 2)
        #expect(Bundle.main.url(forResource: "default_ambient", withExtension: "m4a") != nil)
        #expect(PackageCatalog().isLocallyAvailable("taj_mahal"))
        for checkpoint in installed.package.checkpoints {
            for path in checkpoint.introAudio.values {
                #expect(FileManager.default.fileExists(atPath: installed.fileURL(for: path).path))
            }
            for nugget in checkpoint.nuggets {
                #expect(FileManager.default.fileExists(atPath: installed.targetURL(for: nugget).path))
                #expect(nugget.audio.values.allSatisfy { FileManager.default.fileExists(atPath: installed.fileURL(for: $0).path) })
                #expect(nugget.images.allSatisfy { FileManager.default.fileExists(atPath: installed.fileURL(for: $0).path) })
            }
        }
    }

    @Test @MainActor func partialPackageDropsOnlyUnplayableContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("partial-tour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data([0x00]).write(to: root.appendingPathComponent("audio/playable_en.mp3"))
        let json = """
        {
          "schemaVersion": 1,
          "monument": {
            "id": "partial",
            "name": {"en": "Partial Tour"},
            "languages": ["en", "hi"],
            "overview": {"en": "A partial package"}
          },
          "routes": null,
          "checkpoints": [
            {
              "id": "playable", "order": 0, "name": {"en": "Playable"},
              "mapPosition": {"x": 0.2, "y": 0.3}, "gps": null, "venue": false,
              "intro": {"en": "Playable intro"},
              "introAudio": {"en": "audio/missing_intro.mp3"},
              "nuggets": [{
                "id": "usable", "title": {"en": "Usable"}, "targetImageId": "missing_target",
                "exclusive": false, "text": {"en": "Still available in Browse Mode"},
                "audio": {"en": "audio/playable_en.mp3", "hi": "audio/missing_hi.mp3"}
              }]
            },
            {
              "id": "placeholder", "order": 1, "name": {"en": "Placeholder"},
              "mapPosition": {"x": 0.8, "y": 0.8}, "gps": null, "venue": true,
              "intro": {"en": "Placeholder"}, "introAudio": {},
              "nuggets": [{
                "id": "unusable", "title": {"en": "Unusable"}, "targetImageId": "none",
                "exclusive": false, "text": {"en": "No audio"},
                "audio": {"en": "audio/missing.mp3"}
              }]
            }
          ]
        }
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("tour.json"))

        let installed = try PackageStore().decodeAndValidate(directory: root)
        #expect(installed.package.checkpoints.map(\.id) == ["playable"])
        #expect(installed.package.checkpoints[0].introAudio.isEmpty)
        #expect(installed.package.checkpoints[0].nuggets[0].audio == ["en": "audio/playable_en.mp3"])
        #expect(installed.package.checkpoints[0].nuggets[0].images.isEmpty)
        #expect(installed.package.checkpoints[0].nuggets[0].targetImageIds.isEmpty)
        #expect(installed.displayURLs(for: installed.package.checkpoints[0].nuggets[0]) == [installed.targetURL(for: installed.package.checkpoints[0].nuggets[0])])
        #expect(!FileManager.default.fileExists(atPath: installed.targetURL(for: installed.package.checkpoints[0].nuggets[0]).path))
    }

    @Test @MainActor func alternateTargetIDsDecodeAndSanitizeAdditively() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("target-ids-tour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("targets"), withIntermediateDirectories: true)
        try Data([0]).write(to: root.appendingPathComponent("audio/playable.mp3"))
        try Data([0]).write(to: root.appendingPathComponent("targets/left.jpg"))
        let json = """
        {"schemaVersion":1,"monument":{"id":"targets","name":{"en":"Targets"},"languages":["en"],"overview":{"en":"Targets"}},"routes":null,"checkpoints":[{"id":"cp","order":0,"name":{"en":"CP"},"mapPosition":{"x":0.5,"y":0.5},"gps":null,"venue":false,"intro":{},"introAudio":{},"nuggets":[{"id":"n","title":{"en":"N"},"targetImageId":"primary","targetImageIds":["primary","left","missing","../escape","a/b","left"],"exclusive":false,"images":[],"text":{"en":"N"},"audio":{"en":"audio/playable.mp3"}}]}]}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("tour.json"))

        let nugget = try PackageStore().decodeAndValidate(directory: root).package.checkpoints[0].nuggets[0]
        #expect(nugget.targetImageId == "primary")
        #expect(nugget.targetImageIds == ["left"])
        #expect(nugget.effectiveTargetImageIds == ["primary", "left"])
    }

    @Test @MainActor func galleryPathsAreSanitizedWithoutDroppingNugget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-tour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data([0]).write(to: root.appendingPathComponent("audio/playable.mp3"))
        try Data([0]).write(to: root.appendingPathComponent("images/valid.webp"))
        let json = """
        {"schemaVersion":1,"monument":{"id":"gallery","name":{"en":"Gallery"},"languages":["en"],"overview":{"en":"Gallery"}},"routes":null,"checkpoints":[{"id":"cp","order":0,"name":{"en":"CP"},"mapPosition":{"x":0.5,"y":0.5},"gps":null,"venue":false,"intro":{},"introAudio":{},"nuggets":[{"id":"n","title":{"en":"N"},"targetImageId":"target","exclusive":false,"images":["../outside.webp","images/missing.webp","images/not.jpg","images/valid.webp"],"text":{"en":"N"},"audio":{"en":"audio/playable.mp3"}}]}]}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("tour.json"))

        let installed = try PackageStore().decodeAndValidate(directory: root)
        let nugget = installed.package.checkpoints[0].nuggets[0]
        #expect(nugget.images == ["images/valid.webp"])
        #expect(installed.displayURLs(for: nugget) == [root.appendingPathComponent("images/valid.webp")])
    }

    @Test func healthResponseUsesMonumentIDs() throws {
        let response = try JSONDecoder().decode(
            PackageCatalog.HealthResponse.self,
            from: Data(#"{"monuments":{"taj_mahal":7,"zomato_farmhouse":3,"red_fort":1}}"#.utf8)
        )
        #expect(Set(response.monuments.keys) == ["taj_mahal", "zomato_farmhouse", "red_fort"])
    }

    @Test func tajMapRouteUsesExactNormalizedCoordinates() {
        let route = TajMapCheckpoint.chapters
        #expect(route.map(\.name) == ["Start (Entry)", "Terrace", "Mughal Charbagh", "Mosque", "Great Gate", "Exit"])
        #expect(route.map { $0.point(in: CGSize(width: 1024, height: 1536)) } == [
            CGPoint(x: 562, y: 333),
            CGPoint(x: 371, y: 468),
            CGPoint(x: 692, y: 810),
            CGPoint(x: 386, y: 992),
            CGPoint(x: 643, y: 1168),
            CGPoint(x: 675, y: 1379)
        ])
    }

    @Test @MainActor func tajChapterProgressIsSequentialPersistentAndIdempotent() {
        let suiteName = "MaraudersTests.TajProgress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TajTourProgressStore(defaults: defaults)
        #expect(store.completedChapterCount == 0)
        #expect(store.selectedChapterID == "start")
        #expect(store.chapters.map(\.status) == [.active, .locked, .locked, .locked, .locked, .locked])
        #expect(!store.select("exit"))
        #expect(store.completeSelectedChapter())
        #expect(!store.completeSelectedChapter())
        #expect(store.completedChapterCount == 1)
        #expect(store.select("terrace"))

        let restored = TajTourProgressStore(defaults: defaults)
        #expect(restored.completedChapterCount == 1)
        #expect(restored.selectedChapterID == "terrace")

        for chapter in TajMapCheckpoint.chapters.dropFirst() {
            #expect(restored.select(chapter.id))
            #expect(restored.completeSelectedChapter())
        }
        #expect(restored.completedChapterCount == 6)
        #expect(restored.progress == 1)
        #expect(restored.isComplete)
        #expect(!restored.completeSelectedChapter())
    }

    @Test @MainActor func tajAIInsightCachesOfflineFallbackByLanguage() async {
        let suiteName = "MaraudersTests.TajInsights.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TajAIInsightStore(defaults: defaults)
        let chapter = TajMapCheckpoint.chapters[0]

        await store.load(for: chapter, language: "en")
        #expect(store.state(for: chapter.id, language: "en") == .success(chapter.fallbackAIInformation))
        #expect(defaults.string(forKey: "taj.ai-insight.v2.en.\(chapter.id)") == chapter.fallbackAIInformation)
        #expect(store.state(for: chapter.id, language: "hi") == .idle)
        #expect(defaults.string(forKey: "taj.ai-insight.v2.hi.\(chapter.id)") == nil)

        let restored = TajAIInsightStore(defaults: defaults)
        await restored.load(for: chapter, language: "en")
        #expect(restored.state(for: chapter.id, language: "en") == .success(chapter.fallbackAIInformation))
    }

    @Test func languageFallbackUsesEnglish() {
        let values: LangMap = ["en": "Gateway", "hi": "द्वार"]
        #expect(values.v("hi") == "द्वार")
        #expect(values.v("fr") == "Gateway")
        #expect((["hi": "audio_hi.mp3"] as LangMap).mediaPath("fr") == "audio_hi.mp3")
    }

    @Test func apiUsesAzureAsSingleSource() {
        #expect(API.base == API.azureBase)
        #expect(API.base.absoluteString == "https://marauders-backend.azurewebsites.net")
    }

    @Test func audioDebounceMatchesContract() {
        #expect(AudioTiming.enterHold == 0.3)
        #expect(AudioTiming.exitHold == 1.5)
        #expect(AudioTiming.fadeIn == 0.4)
        #expect(AudioTiming.fadeOut == 0.6)
        #expect(AudioTiming.crossfade == 0.5)
    }

    @Test @MainActor func aiGuideKeepsConversationHistory() async {
        let service = AIGuideChatService(engine: StubAnswerEngine())
        let context = AIGuideContext(
            monumentID: "taj_mahal",
            monumentName: "Taj Mahal",
            checkpointID: "great-gate",
            checkpointName: "Great Gate",
            language: "en"
        )

        await service.send("Why does the lettering change size?", context: context)

        #expect(service.messages.count == 2)
        #expect(service.messages[0].role == .user)
        #expect(service.messages[0].text == "Why does the lettering change size?")
        #expect(service.messages[1].role == .guide)
        #expect(service.messages[1].text == "The scaling compensates for viewing perspective.")
        #expect(service.errorMessage == nil)
        #expect(!service.isLoading)
    }

    @Test @MainActor func profileAndPreferencesPersist() {
        let suiteName = "MaraudersTests.Profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let session = AppSession(defaults: defaults)
        #expect(session.userName == "Swift Dzire LXI")

        session.updateProfile(
            name: "Test Explorer",
            email: "explorer@example.com",
            gender: "Non-binary",
            dateOfBirth: Date(timeIntervalSince1970: 631_152_000),
            disabilityStatus: .yes,
            accessibilityNotes: "Step-free routes preferred"
        )
        session.appLanguage = .hindi
        session.prefersLargeText = true
        session.prefersHighContrast = true

        let restored = AppSession(defaults: defaults)
        #expect(restored.userName == "Test Explorer")
        #expect(restored.email == "explorer@example.com")
        #expect(restored.gender == "Non-binary")
        #expect(restored.dateOfBirth == Date(timeIntervalSince1970: 631_152_000))
        #expect(restored.disabilityStatus == .yes)
        #expect(restored.accessibilityNotes == "Step-free routes preferred")
        #expect(restored.appLanguage == .hindi)
        #expect(restored.prefersLargeText)
        #expect(restored.prefersHighContrast)
    }
}

private struct StubAnswerEngine: AnswerEngine {
    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String, skipAudio: Bool
    ) async throws -> AskResponse {
        #expect(text == "Why does the lettering change size?")
        #expect(audioBase64 == nil)
        #expect(checkpointId == "great-gate")
        #expect(monumentId == "taj_mahal")
        #expect(lang == "en")
        #expect(skipAudio)
        return AskResponse(
            question: text ?? "",
            text: "The scaling compensates for viewing perspective.",
            audioBase64: ""
        )
    }
}
