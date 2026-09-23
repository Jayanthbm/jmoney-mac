import SwiftUI

/// One transaction row, shared by the Transactions list and the dashboard's
/// "Today's Activity" drill-down so both render identically.
///
/// Mirrors `TransactionCard.tsx`: the category is the title (falling back to
/// "No Category"), the description is the subtitle, and the amount carries an
/// explicit sign with income green and expense red.
///
/// Two deliberate differences from the RN card, both documented in the feature
/// matrix:
/// * the category glyph is the stored Material icon name (`category_app_icon`)
///   translated through the shared `CategoryIcon` table — the RN card hands the raw
///   name to `MaterialIcons`;
/// * the "not yet uploaded" cloud badge is omitted while the sync engine does not
///   exist, since every row would be flagged and the state would be meaningless.
struct TransactionRow: View {
    let transaction: Transaction

    @State private var isHovered = false

    private var isIncome: Bool { transaction.type == "Income" }

    private var categoryTitle: String {
        transaction.categoryName.flatMap { $0.isEmpty ? nil : $0 } ?? "No Category"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill((isIncome ? Color.green : Color.accentColor).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: CategoryIcon.transactionSymbol(transaction.categoryAppIcon))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isIncome ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(categoryTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if let payee = nonEmpty(transaction.payeeName) {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(payee)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let group = nonEmpty(transaction.groupName) {
                        Label(group, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let description = nonEmpty(transaction.description) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                attachments
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(isIncome ? "+" : "-") \(AppFormat.currency(transaction.amount))")
                    .font(.body.weight(.bold))
                    .foregroundStyle(isIncome ? Color.green : Color.red)
                    .monospacedDigit()
                Text(AppFormat.preciseTimestamp(transaction.transactionTimestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if transaction.syncStatus == 1 {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Not yet uploaded")
                        .accessibilityLabel("Not yet uploaded")
                }
            }
        }
        .padding(12)
        .frame(height: 72)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.4 : 0.2),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.1) : Color.black.opacity(0.03),
            radius: isHovered ? 10 : 4,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
    }

    /// The product link and map affordances from the RN card footer.
    @ViewBuilder
    private var attachments: some View {
        HStack(spacing: 8) {
            if let link = nonEmpty(transaction.productLink),
               let url = URL(string: link) {
                Link(destination: url) {
                    Label("Product link", systemImage: "link")
                        .font(.caption2)
                }
                .help(link)
            }

            if let latitude = transaction.latitude, let longitude = transaction.longitude,
               let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)") {
                Link(destination: url) {
                    Label("Location", systemImage: "map")
                        .font(.caption2)
                }
                .help("\(latitude), \(longitude)")
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// The date group header: the day and that day's net, mirroring
/// `TransactionSectionHeader.tsx`.
///
/// Note the source's exact formatting quirk: a positive total gets a `+` prefix,
/// a negative one does **not** get a `-` (the currency helper drops the sign) and
/// is distinguished by colour.
struct TransactionDayHeader: View {
    let section: TransactionService.DaySection

    var body: some View {
        HStack(spacing: 8) {
            Text(AppFormat.monthDayYear(section.date).uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text("\(section.total >= 0 ? "+" : "")\(AppFormat.currency(section.total))")
                .font(.caption.weight(.bold))
                .foregroundStyle(section.total >= 0 ? Color.green : Color.red)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Phase 17: the header's sign-dropping quirk (a negative net shows no `-`,
    /// only red) is colour-only information — VoiceOver would read a bare amount.
    /// The direction is therefore spoken explicitly.
    private var accessibilityLabel: String {
        let direction = section.total >= 0 ? "increased" : "decreased"
        return "\(AppFormat.monthDayYear(section.date)), net \(direction) \(AppFormat.currency(section.total))"
    }
}
