import SwiftUI

/// Progress ring.
///
/// The RN `CircularProgress` fakes an arc with four border colours (0/25/50/75%
/// segments) because React Native has no path-stroke primitive. Here the same
/// inputs — a 0…100 percentage, colour, centre value, and label — render as a
/// real arc, which is the macOS-appropriate presentation (MACOS_ARCHITECTURE.md §4).
struct CircularProgressView: View {
    let percentage: Double
    var color: Color = .accentColor
    let value: String
    let label: String
    var size: Double = 76
    var lineWidth: Double = 6

    private var clamped: Double { min(1, max(0, percentage / 100)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Horizontal progress bar. Clamps the fill at 0…100% exactly like the RN
/// `ProgressBar`; callers may still display an unclamped percentage label.
struct ProgressBarView: View {
    let progress: Double
    var color: Color = .accentColor
    var height: Double = 8

    private var clamped: Double { min(100, max(0, progress)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * clamped / 100)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
