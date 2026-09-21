import SwiftUI

/// One goal row, mirroring `GoalCard.tsx`.
///
/// The card's information is kept in full, laid out for a desktop list: the logo
/// (or the 🎯 placeholder) and name on one line, a `Saved` / `Target` pair of
/// columns, the progress bar, and the `% Complete` / `left` footer.
struct GoalRow: View {
    let goal: Goal
    let info: GoalService.CardInfo

    private var accent: Color { info.isComplete ? .green : .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            stats
            ProgressBarView(progress: info.progress, color: accent, height: 10)
            footer
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(goal.name). \(info.percentage) percent complete. "
                + "Saved \(AppFormat.currency(goal.currentAmount)) "
                + "of \(AppFormat.currency(goal.goalAmount))."
        )
        .accessibilityValue("\(AppFormat.currency(info.remaining)) left")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            logo
            Text(goal.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
    }

    /// `item.logo.startsWith('http')` picks the remote image; anything else —
    /// including an empty string — falls back to the emoji tile.
    @ViewBuilder
    private var logo: some View {
        if let url = remoteLogoURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderLogo
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            placeholderLogo
        }
    }

    private var remoteLogoURL: URL? {
        guard let logo = goal.logo, !logo.isEmpty, logo.hasPrefix("http") else { return nil }
        return URL(string: logo)
    }

    private var placeholderLogo: some View {
        Text("🎯")
            .font(.system(size: 14))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color(nsColor: .quaternaryLabelColor)))
            .accessibilityHidden(true)
    }

    private var stats: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Saved")
                Spacer(minLength: 8)
                Text("Target")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text(AppFormat.currency(goal.currentAmount))
                    .foregroundStyle(.green)
                Spacer(minLength: 8)
                Text(AppFormat.currency(goal.goalAmount))
                    .foregroundStyle(.primary)
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack {
            Text("\(info.percentage)% Complete")
                .font(.caption.weight(.heavy))
                .foregroundStyle(accent)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text("\(AppFormat.currency(info.remaining)) left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
