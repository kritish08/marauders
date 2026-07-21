import ARKit
import SwiftUI

struct ARImageTrackingView: UIViewRepresentable {
    let session: TourSession
    let isSuppressed: Bool
    let allowedTargetIDs: Set<String>?
    var snapshotProxy: CameraSnapshotProxy? = nil
    let onFound: (Checkpoint, Nugget, UIImage?) -> Void
    let onLost: (Nugget) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        context.coordinator.attach(view)
        snapshotProxy?.capture = { [weak view] in view?.snapshot() }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.update(parent: self)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private struct Candidate {
            let value: (Checkpoint, Nugget)
            var distance: Float
            let heldSince: Date
        }

        private var parent: ARImageTrackingView
        private weak var view: ARSCNView?
        private var nuggetByTarget: [String: (Checkpoint, Nugget)] = [:]
        private var candidates: [String: Candidate] = [:]
        private var selectedTargetID: String?
        private var suppressed: Bool

        init(parent: ARImageTrackingView) {
            self.parent = parent
            suppressed = parent.isSuppressed
            super.init()
            indexTargets()
        }

        func attach(_ view: ARSCNView) {
            self.view = view
            run(on: view)
        }

        func update(parent: ARImageTrackingView) {
            let needsTargetReindex = self.parent.session !== parent.session
                || self.parent.allowedTargetIDs != parent.allowedTargetIDs
            self.parent = parent
            let wasSuppressed = suppressed
            suppressed = parent.isSuppressed
            var targetIDsChanged = false
            if needsTargetReindex {
                let previousTargetIDs = Set(nuggetByTarget.keys)
                let selectedNugget = selectedTargetID.flatMap { nuggetByTarget[$0]?.1 }
                indexTargets()
                targetIDsChanged = previousTargetIDs != Set(nuggetByTarget.keys)

                if targetIDsChanged {
                    clearTrackingState(lostNugget: selectedNugget)
                    if let view { run(on: view) }
                } else {
                    candidates = candidates.reduce(into: [:]) { result, entry in
                        guard let value = nuggetByTarget[entry.key] else { return }
                        result[entry.key] = Candidate(
                            value: value,
                            distance: entry.value.distance,
                            heldSince: entry.value.heldSince
                        )
                    }
                    if selectedTargetID.flatMap({ nuggetByTarget[$0] }) == nil {
                        selectedTargetID = nil
                    }
                }
            }
            if wasSuppressed, !suppressed, !targetIDsChanged { emitCurrentSelection() }
        }

        private func indexTargets() {
            nuggetByTarget.removeAll(keepingCapacity: true)
            for checkpoint in parent.session.installed.package.checkpoints {
                for nugget in checkpoint.nuggets {
                    for targetID in nugget.effectiveTargetImageIds
                    where parent.allowedTargetIDs?.contains(targetID) ?? true {
                        nuggetByTarget[targetID] = (checkpoint, nugget)
                    }
                }
            }
        }

        private func clearTrackingState(lostNugget: Nugget?) {
            candidates.removeAll(keepingCapacity: true)
            selectedTargetID = nil
            guard let lostNugget, !suppressed else { return }
            let onLost = parent.onLost
            Task { @MainActor in onLost(lostNugget) }
        }

        private func run(on view: ARSCNView) {
            let references = Set(nuggetByTarget.compactMap { targetID, value -> ARReferenceImage? in
                let url = parent.session.installed.targetURL(forID: targetID)
                guard let image = Self.normalizedCGImage(contentsOfFile: url.path) else { return nil }
                let reference = ARReferenceImage(
                    image, orientation: .up,
                    physicalWidth: value.1.targetPhysicalWidthM.map { CGFloat($0) } ?? 0.18
                )
                reference.name = targetID
                return reference
            })
            guard !references.isEmpty else {
                Task { @MainActor in self.parent.onFailure() }
                return
            }
            let configuration = ARImageTrackingConfiguration()
            configuration.trackingImages = references
            configuration.maximumNumberOfTrackedImages = min(references.count, 4)
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        // UIImage.cgImage strips the file's EXIF rotation, so a portrait-shot target JPG
        // would be registered sideways and only match when the phone cancels the rotation.
        private static func normalizedCGImage(contentsOfFile path: String) -> CGImage? {
            guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
            if uiImage.imageOrientation == .up { return uiImage.cgImage }
            let format = UIGraphicsImageRendererFormat()
            format.scale = uiImage.scale
            let renderer = UIGraphicsImageRenderer(size: uiImage.size, format: format)
            let normalized = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
            }
            return normalized.cgImage
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARImageAnchor else { return nil }
            let node = SCNNode()
            let plane = SCNPlane(width: 0.2, height: 0.2)
            plane.cornerRadius = 0.025
            plane.firstMaterial?.diffuse.contents = UIColor(Theme.primary).withAlphaComponent(0.18)
            plane.firstMaterial?.emission.contents = UIColor(Theme.goldLight).withAlphaComponent(0.55)
            let glow = SCNNode(geometry: plane)
            glow.eulerAngles.x = -.pi / 2
            glow.position.y = 0.002
            node.addChildNode(glow)
            return node
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            updateCandidates(anchors)
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            updateCandidates(anchors)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for case let anchor as ARImageAnchor in anchors {
                if let name = anchor.referenceImage.name { candidates[name] = nil }
            }
            chooseSelection()
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in self.parent.onFailure() }
        }

        private func updateCandidates(_ anchors: [ARAnchor]) {
            for case let anchor as ARImageAnchor in anchors {
                guard let name = anchor.referenceImage.name, let value = nuggetByTarget[name] else { continue }
                if anchor.isTracked {
                    let translation = anchor.transform.columns.3
                    let distance = simd_length(SIMD3<Float>(translation.x, translation.y, translation.z))
                    let heldSince = candidates[name]?.heldSince ?? .now
                    candidates[name] = Candidate(value: value, distance: max(distance, 0.05), heldSince: heldSince)
                } else {
                    candidates[name] = nil
                }
            }
            chooseSelection()
        }

        private func chooseSelection() {
            let previous = selectedTargetID
            let ranked = candidates.sorted { lhs, rhs in
                let lhsScore = score(lhs.value)
                let rhsScore = score(rhs.value)
                if abs(lhsScore - rhsScore) < 0.12 { return lhs.value.heldSince < rhs.value.heldSince }
                return lhsScore > rhsScore
            }
            var next = ranked.first?.key

            if let previous, let current = candidates[previous], let strongest = ranked.first?.value {
                let currentScore = score(current)
                let strongestScore = score(strongest)
                if currentScore >= strongestScore * 0.9 { next = previous }
            }
            guard next != previous else { return }
            selectedTargetID = next

            if let previous, let nugget = nuggetByTarget[previous]?.1, !suppressed {
                Task { @MainActor in self.parent.onLost(nugget) }
            }
            emitCurrentSelection()
        }

        private func score(_ candidate: Candidate) -> Float {
            let holdBonus = min(Float(Date().timeIntervalSince(candidate.heldSince)) * 0.06, 0.25)
            return (1 / candidate.distance) + holdBonus
        }

        private func emitCurrentSelection() {
            guard !suppressed, let selectedTargetID, let value = nuggetByTarget[selectedTargetID] else { return }
            Task { @MainActor in
                let frame = self.view?.snapshot()
                self.parent.onFound(value.0, value.1, frame)
            }
        }
    }
}
