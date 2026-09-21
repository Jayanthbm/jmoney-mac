import SwiftUI

/// One payee row, mirroring `PayeeCard.tsx`.
///
/// The logo is the payee's `logo` column when it starts with `http` — the source's
/// exact test — and the name's initial otherwise. Unlike categories there is no
/// placeholder icon to fall back to.
struct PayeeRow: View {
    let payee: Payee
    var viewMode: ViewModePreference.ListGridMode = .list

    var body: some View {
        if viewMode == .grid {
            VStack(spacing: 8) {
                logo(size: 44, fontSize: 16)
                Text(payee.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(payee.name)
        } else {
            HStack(spacing: 10) {
                logo(size: 30, fontSize: 12)
                Text(payee.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(payee.name)
        }
    }

    @ViewBuilder
    private func logo(size: CGFloat, fontSize: CGFloat) -> some View {
        if let url = remoteLogoURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                initialTile(size: size, fontSize: fontSize)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialTile(size: size, fontSize: fontSize)
        }
    }

    private var remoteLogoURL: URL? {
        guard let logo = payee.logo, logo.hasPrefix("http") else { return nil }
        return URL(string: logo)
    }

    private func initialTile(size: CGFloat, fontSize: CGFloat) -> some View {
        Text(String(payee.name.prefix(1)).uppercased())
            .font(.system(size: fontSize, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}
