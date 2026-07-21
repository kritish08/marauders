import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// Lets the AR camera hand out on-demand frame snapshots without exposing the ARSCNView.
final class CameraSnapshotProxy {
    var capture: (@MainActor () -> UIImage?)?
}

// "What's this?" — identifies whatever the camera sees, even when it isn't an AR target.
// iOS 27 Foundation Models vision runs fully on-device; otherwise falls back to the
// backend /ask endpoint with an image payload (see BACKEND_HANDOFF_iOS27 Task 3).
@MainActor
final class VisionAnswerService: ObservableObject {
    enum State: Equatable {
        case idle, thinking, answered(String), failed(String)
    }

    @Published private(set) var state: State = .idle

    static var supportsOnDeviceVision: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *) else { return false }
        let model = SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.vision)
        #else
        return false
        #endif
    }

    func identify(image: UIImage, monumentName: String, checkpointID: String, monumentID: String, lang: String) {
        state = .thinking
        Task {
            if Self.supportsOnDeviceVision, let answer = await onDeviceAnswer(image: image, monumentName: monumentName, lang: lang) {
                state = .answered(answer)
                return
            }
            do {
                let answer = try await remoteAnswer(image: image, checkpointID: checkpointID, monumentID: monumentID, lang: lang)
                state = .answered(answer)
            } catch {
                state = .failed("The guide could not identify this view. Try a mapped AR target, or ask by text or voice.")
            }
        }
    }

    func reset() { state = .idle }

    private func onDeviceAnswer(image: UIImage, monumentName: String, lang: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *), let cgImage = image.cgImage else { return nil }
        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: lang) ?? "English"
        let session = LanguageModelSession(instructions: """
        You are Marauders, an expert tour guide standing with a visitor at \(monumentName).
        Identify what the visitor's camera is pointing at and share one vivid, factual detail about it.
        Answer in \(languageName), in at most three sentences. If unsure, describe what is visible and relate it to \(monumentName).
        """)
        let response = try? await session.respond {
            "What is the visitor looking at in this photo?"
            Attachment(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        }
        return response?.content
        #else
        return nil
        #endif
    }

    private struct VisionAskRequest: Encodable {
        let monumentId: String
        let checkpointId: String
        let lang: String
        let text: String
        let imageBase64: String
        let skipAudio: Bool
    }

    private func remoteAnswer(image: UIImage, checkpointID: String, monumentID: String, lang: String) async throws -> String {
        guard !API.appKey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard let jpeg = downscaled(image).jpegData(compressionQuality: 0.6) else { throw URLError(.cannotCreateFile) }
        var request = URLRequest(url: API.base.appendingPathComponent("ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(API.appKey, forHTTPHeaderField: "X-App-Key")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(VisionAskRequest(
            monumentId: monumentID, checkpointId: checkpointID, lang: lang,
            text: "What is the visitor looking at in the attached photo? Answer in at most three sentences.",
            imageBase64: jpeg.base64EncodedString(), skipAudio: true
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(AskResponse.self, from: data)
        guard !decoded.text.isEmpty else { throw URLError(.zeroByteResource) }
        return decoded.text
    }

    private func downscaled(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
