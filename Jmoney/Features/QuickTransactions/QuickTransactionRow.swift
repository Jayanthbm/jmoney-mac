import SwiftUI

/// One template, in either of the quick-transactions screen's two layouts.
///
/// Ports `QuickTransactionCard.tsx` (the Card view: a large tile with a
/// plus/minus-circle glyph and the amount, or "Flexible" when the template has none)
/// and the inline list row in `app/quick-transactions.tsx` (a glyph box, the name,
/// the "`<Type>` Template" meta line and the amount).
struct QuickTransactionRow: View {
    let template: QuickTransaction
    var style: ViewModePreference.CardListMode = .card
    /// The Card view's corner `×` (the list view uses a trailing delete glyph).
    var onDelete: (() -> Void)?

    private var isIncome: Bool { template.type == QuickTransactionService.Kind.income.rawValue }

    private var accent: Color { isIncome ? .green : .red }

    @State private var isHovered = false

    var body: some View {
        Group {
            if style == .card {
                card
            } else {
                listRow
            }
        }
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
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Card view

    private var card: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                Image(systemName: isIncome ? "plus.circle" : "minus.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                Text(template.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Text(amountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .topTrailing) {
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Delete template")
                .accessibilityLabel("Delete \(template.name)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name), \(amountText), \(template.type) template")
    }

    // MARK: - List view

    private var listRow: some View {
        HStack(spacing: 12) {
            Image(systemName: isIncome ? "plus" : "minus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(template.type) Template")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.body.weight(.bold))
                .foregroundStyle(accent)
                .monospacedDigit()

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete template")
                .accessibilityLabel("Delete \(template.name)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// `item.amount ? formatCurrency(item.amount) : 'Flexible'`.
    private var amountText: String {
        guard let amount = template.amount else { return "Flexible" }
        return AppFormat.currency(amount)
    }
}
