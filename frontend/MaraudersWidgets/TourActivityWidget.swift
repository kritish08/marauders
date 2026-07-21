import ActivityKit
import SwiftUI
import WidgetKit

private let heritageGold = Color(red: 0.78, green: 0.62, blue: 0.26)
private let heritageTeal = Color(red: 0.16, green: 0.53, blue: 0.5)

struct TourActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TourActivityAttributes.self) { context in
            LockScreenTourView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.72))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "building.columns.fill")
                        .font(.title2).foregroundStyle(heritageGold)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    progressRing(context.state, size: 36)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.monumentName)
                            .font(.headline).foregroundStyle(.white).lineLimit(1)
                        Text(context.state.chapterName)
                            .font(.caption).foregroundStyle(heritageGold).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isNarrating ? "waveform" : "headphones")
                            .foregroundStyle(heritageTeal)
                        Text(context.state.isNarrating ? "Narrating this secret…" : "Point the camera at a target to hear its story")
                            .font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Spacer()
                        Text("\(context.state.completedChapters)/\(context.state.totalChapters)")
                            .font(.caption.bold()).foregroundStyle(heritageGold)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.isNarrating ? "waveform" : "building.columns.fill")
                    .foregroundStyle(heritageGold)
            } compactTrailing: {
                progressRing(context.state, size: 16)
            } minimal: {
                progressRing(context.state, size: 16)
            }
        }
    }

    private func progressRing(_ state: TourActivityAttributes.ContentState, size: CGFloat) -> some View {
        let progress = state.totalChapters > 0 ? Double(state.completedChapters) / Double(state.totalChapters) : 0
        return ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: progress)
                .stroke(heritageTeal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct LockScreenTourView: View {
    let context: ActivityViewContext<TourActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.columns.fill")
                .font(.title).foregroundStyle(heritageGold)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.monumentName)
                    .font(.headline).foregroundStyle(.white)
                Text(context.state.chapterName)
                    .font(.subheadline).foregroundStyle(heritageGold)
                Label(
                    context.state.isNarrating ? "Narrating this secret…" : "\(context.state.completedChapters) of \(context.state.totalChapters) chapters complete",
                    systemImage: context.state.isNarrating ? "waveform" : "checkmark.seal.fill"
                )
                .font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                Circle().trim(from: 0, to: context.state.totalChapters > 0 ? Double(context.state.completedChapters) / Double(context.state.totalChapters) : 0)
                    .stroke(heritageTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(context.state.completedChapters)/\(context.state.totalChapters)")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
        }
        .padding(16)
    }
}
