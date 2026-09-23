import SwiftUI

/// One payee row, mirroring `PayeeCard.tsx`.
///
/// The logo is the payee's `logo` column when it starts with `http` — the source's
/// exact test — and the name's initial otherwise. Unlike categories there is no
/// placeholder icon to fall back to.
struct PayeeRow: View {
    let payee: Payee
    var viewMode: ViewModePreference.ListGridMode = .list

    @State private var isHovered = false

    var body: some View {
        Group {
            if viewMode == .grid {
                VStack(spacing: 8) {
                    logo(size: 44, fontSize: 16)
                    Text(payee.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            } else {
                HStack(spacing: 12) {
                    logo(size: 32, fontSize: 13)
                    Text(payee.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .padding(12)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(payee.name)
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
