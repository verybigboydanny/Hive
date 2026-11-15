import SwiftUI

extension View {
    @ViewBuilder
    func hiveGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(HiveGlassStyle.make(tint: tint, interactive: interactive), in: shape)
        } else {
            hiveFrostedGlass(in: shape, tint: tint)
        }
        #else
        hiveFrostedGlass(in: shape, tint: tint)
        #endif
    }

    private func hiveFrostedGlass<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        background {
            ZStack {
                if let tint {
                    shape.fill(tint.opacity(0.55))
                }
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.38), .white.opacity(0.04), .white.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private enum HiveGlassStyle {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}
#endif

struct HiveGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
