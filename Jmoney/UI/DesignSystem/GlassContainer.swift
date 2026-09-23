import SwiftUI

/// Reusable Liquid Glass container component for macOS 15+ design language.
struct GlassContainer<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var material: Material = .ultraThinMaterial
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding()
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, material: Material = .ultraThinMaterial) -> some View {
        GlassContainer(cornerRadius: cornerRadius, material: material) {
            self
        }
    }
}
