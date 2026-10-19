import ActivityKit
import CoroKit
import SwiftUI
import WidgetKit

/// Lock Screen, Dynamic Island and — through the `.small` supplemental family — CarPlay / Apple Watch.
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.current)
                            .font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                        if let next = context.state.next {
                            Text(next).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Text(context.state.current).font(.caption2).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "music.note")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

struct LyricsActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            compact
        } else {
            full
        }
    }

    /// CarPlay / Watch: big current line, glanceable next line; sizes come from Settings.
    private var compact: some View {
        let style = state.carPlayStyle
        return VStack(alignment: .leading, spacing: 4) {
            Text(state.current)
                .font(.system(size: style.currentSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(style.currentLineLimit)
                .minimumScaleFactor(0.6)
            if let nextSize = style.nextSize, let next = state.next {
                Text(next)
                    .font(.system(size: nextSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black)
    }

    /// Lock Screen.
    private var full: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                Text("\(state.title) · \(state.artist)").lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))

            if let previous = state.previous {
                Text(previous).font(.subheadline).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            }
            Text(state.current)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let next = state.next {
                Text(next).font(.subheadline).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            ProgressView(value: state.progress).tint(.white.opacity(0.8))
        }
        .padding()
    }
}
