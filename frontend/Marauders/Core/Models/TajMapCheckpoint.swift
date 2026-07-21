import CoreGraphics
import Foundation

enum CheckpointStatus: String, Codable, Equatable {
    case completed, active, available, upcoming, locked
}

struct TajMapCheckpoint: Identifiable, Codable, Equatable {
    let id: String
    let chapterNumber: Int
    let name: String
    let normalizedX: Double
    let normalizedY: Double
    let verifiedInformation: String
    let fallbackAIInformation: String
    let architecture: String
    let historicalContext: String
    let interestingFact: String
    let visitorGuidance: String
    let arAssetName: String?
    var status: CheckpointStatus

    var order: Int { chapterNumber - 1 }
    var normalizedPosition: CGPoint { CGPoint(x: normalizedX, y: normalizedY) }

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * normalizedX, y: size.height * normalizedY)
    }

    func withStatus(_ status: CheckpointStatus) -> TajMapCheckpoint {
        var copy = self
        copy.status = status
        return copy
    }

    static let chapters: [TajMapCheckpoint] = [
        TajMapCheckpoint(
            id: "start", chapterNumber: 1, name: "Start (Entry)",
            normalizedX: 562.0 / 1024.0, normalizedY: 333.0 / 1536.0,
            verifiedInformation: "The Taj Mahal is a white-marble mausoleum beside the Yamuna in Agra, commissioned by Mughal emperor Shah Jahan in memory of Mumtaz Mahal.",
            fallbackAIInformation: "Begin by orienting yourself to the riverfront complex. This chapter uses the verified monument overview because the offline package does not contain a separate entry narrative.",
            architecture: "The complex is arranged as a carefully ordered sequence of gateways, gardens, raised platforms and the riverfront mausoleum.",
            historicalContext: "The bundled guide dates the monument's completion to 1653 and identifies it as a UNESCO World Heritage Site.",
            interestingFact: "The approach is designed as a sequence of framed views rather than a single uninterrupted reveal.",
            visitorGuidance: "Follow posted entry guidance and pause here to understand the route before continuing.",
            arAssetName: nil, status: .active
        ),
        TajMapCheckpoint(
            id: "terrace", chapterNumber: 2, name: "Terrace",
            normalizedX: 371.0 / 1024.0, normalizedY: 468.0 / 1536.0,
            verifiedInformation: "The Yamuna terrace opens toward Mehtab Bagh across the river, a garden aligned with the Taj Mahal.",
            fallbackAIInformation: "The offline guide treats stories of a black-marble twin as legend and notes that archaeological work did not establish such a monument.",
            architecture: "The riverfront terrace extends the composition beyond the mausoleum toward the Yamuna and the aligned garden opposite.",
            historicalContext: "Mehtab Bagh and its alignment form part of the wider riverfront landscape associated with the Taj Mahal.",
            interestingFact: "The so-called Black Taj remains a legend, not a verified companion monument.",
            visitorGuidance: "Look across the river toward Mehtab Bagh and compare its axis with the Taj.",
            arAssetName: nil, status: .locked
        ),
        TajMapCheckpoint(
            id: "mughal-charbagh", chapterNumber: 3, name: "Mughal Charbagh",
            normalizedX: 692.0 / 1024.0, normalizedY: 810.0 / 1536.0,
            verifiedInformation: "The charbagh follows the Persian four-garden idea of paradise, using water channels and balanced sections to organize the landscape.",
            fallbackAIInformation: "The central water axis and reflecting pool reinforce symmetry and guide the eye toward the mausoleum's dome.",
            architecture: "Geometric garden divisions, water channels and long sightlines bind the landscape to the central monument.",
            historicalContext: "The four-part garden is a major design tradition in Mughal landscapes and carries associations with paradise.",
            interestingFact: "The reflecting pool is both a visual feature and a strong directional line through the garden.",
            visitorGuidance: "Use the water axis to study how symmetry directs attention toward the dome.",
            arAssetName: nil, status: .locked
        ),
        TajMapCheckpoint(
            id: "mosque", chapterNumber: 4, name: "Mosque",
            normalizedX: 386.0 / 1024.0, normalizedY: 992.0 / 1536.0,
            verifiedInformation: "The mosque is part of the riverfront composition united by the main marble platform with the tomb and its balancing pavilion.",
            fallbackAIInformation: "The local package has limited mosque-specific commentary, so this chapter avoids unsupported detail and focuses on its verified role in the ensemble.",
            architecture: "Its placement contributes to the balanced composition around the central tomb.",
            historicalContext: "The mosque belongs to the ceremonial and architectural ensemble rather than standing as an isolated building.",
            interestingFact: "The platform visually unifies multiple buildings into one composition.",
            visitorGuidance: "Respect access restrictions and on-site worship guidance; use the exterior view to compare the ensemble's balance.",
            arAssetName: nil, status: .locked
        ),
        TajMapCheckpoint(
            id: "great-gate", chapterNumber: 5, name: "Great Gate",
            normalizedX: 643.0 / 1024.0, normalizedY: 1168.0 / 1536.0,
            verifiedInformation: "The Great Gate, Darwaza-i-Rauza, controls the first framed view of the Taj and combines red sandstone, white-marble detail and calligraphy.",
            fallbackAIInformation: "Its lettering grows larger toward the top so the inscription appears more even when viewed from ground level.",
            architecture: "The monumental arch frames the mausoleum, while inlaid calligraphy and contrasting stone articulate its surface.",
            historicalContext: "The gate choreographs the visitor's transition from the outer approach into the garden sequence.",
            interestingFact: "The bundled guide identifies the calligraphic material as inlaid jasper and explains its optical scaling.",
            visitorGuidance: "At the threshold, compare the framed Taj while stepping backward and forward to observe the perspective effect.",
            arAssetName: "taj_great_gate", status: .locked
        ),
        TajMapCheckpoint(
            id: "exit", chapterNumber: 6, name: "Exit",
            normalizedX: 675.0 / 1024.0, normalizedY: 1379.0 / 1536.0,
            verifiedInformation: "This final chapter closes the guided route. The offline package does not provide a separate historical narrative for the exit point.",
            fallbackAIInformation: "Review the sequence of riverfront terrace, garden, mosque and gateway as parts of one deliberately ordered complex.",
            architecture: "The exit is treated as a route transition rather than a separately verified monument feature.",
            historicalContext: "Completing the route provides an opportunity to reconsider how movement, framing and symmetry shape the visit.",
            interestingFact: "The experience of the Taj changes as the same spaces are seen in reverse order while leaving.",
            visitorGuidance: "Follow the official exit signs, retain your belongings and comply with site staff instructions.",
            arAssetName: nil, status: .locked
        )
    ]
}
