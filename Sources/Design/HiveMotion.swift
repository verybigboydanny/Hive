import SwiftUI

enum HiveMotion {
    static var spring: Animation {
        .spring(response: 0.42, dampingFraction: 0.82)
    }

    static var bouncy: Animation {
        .spring(response: 0.34, dampingFraction: 0.68)
    }

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : animation
    }
}

private struct HiveAppearModifier: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : HiveMotion.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

private struct HiveHoverModifier: ViewModifier {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? scale : 1)
            .shadow(
                color: .black.opacity(isHovering ? 0.16 : 0),
                radius: isHovering ? 12 : 0,
                y: isHovering ? 6 : 0
            )
            .onHover { hovering in
                withAnimation(HiveMotion.resolved(HiveMotion.bouncy, reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
    }
}

private struct HiveFloatModifier: ViewModifier {
    let distance: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    func body(content: Content) -> some View {
        content
            .offset(y: isFloating ? -distance : distance)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    isFloating = true
                }
            }
    }
}

extension View {
    func hiveAppear(delay: Double = 0) -> some View {
        modifier(HiveAppearModifier(delay: delay))
    }

    func hiveHover(scale: CGFloat = 1.02) -> some View {
        modifier(HiveHoverModifier(scale: scale))
    }

    func hiveFloat(distance: CGFloat = 5) -> some View {
        modifier(HiveFloatModifier(distance: distance))
    }
}

struct HivePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HivePressStyle {
    static var hivePress: HivePressStyle { HivePressStyle() }
}

struct HivePulseDot: View {
    let color: Color
    var size: Double = HiveMetrics.statusDotSize
    var isPulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.45))
                    .scaleEffect(isExpanded ? 2.6 : 1)
                    .opacity(isExpanded ? 0 : 0.9)
            }
            Circle()
                .fill(color)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard isPulsing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                isExpanded = true
            }
        }
    }
}
