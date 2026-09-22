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

    private var isIncome: Bool { transaction.type == "Income" }

    private var categoryTitle: String {
        transaction.categoryName.flatMap { $0.isEmpty ? nil : $0 } ?? "No Category"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: CategoryIcon.transactionSymbol(transaction.categoryAppIcon))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isIncome ? Color.green : Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill((isIncome ? Color.green : Color.accentColor).opacity(0.15))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(categoryTitle)
                        .font(.body)
                        .lineLimit(1)

                    if let payee = nonEmpty(transaction.payeeName) {
                        Text(payee)
                            .font(.caption)
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

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(isIncome ? "+" : "-") \(AppFormat.currency(transaction.amount))")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isIncome ? Color.green : Color.red)
                    .monospacedDigit()
                Text(AppFormat.preciseTimestamp(transaction.transactionTimestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                // The RN card's "not yet uploaded" indicator, deferred in Phase 7
                // while no sync engine existed (every row would have been flagged).
                if transaction.syncStatus == 1 {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Not yet uploaded")
                        .accessibilityLabel("Not yet uploaded")
                }
            }
        }
        .padding(.vertical, 3)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppFormat.monthDayYear(section.date)), net \(AppFormat.currency(section.total))")
    }
}
