import SwiftUI

struct HiveAmbientBackground: View {
    var forced = false

    @Environment(\.hiveAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HiveSettingsKey.ambient) private var isEnabled = true

    var body: some View {
        if (isEnabled || forced) && !accent.isFrosted {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: points(at: context.date.timeIntervalSinceReferenceDate),
                    colors: colors
                )
                .opacity(colorScheme == .dark ? 0.34 : 0.26)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var colors: [Color] {
        let base = accent.color
        let glow = accent.glow
        return [
            base, glow, base.opacity(0.4),
            glow.opacity(0.5), base, glow.opacity(0.6),
            base.opacity(0.3), glow, base
        ]
    }

    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)
        func drift(_ base: Float, _ phase: Float, _ speed: Float, _ amount: Float) -> Float {
            base + amount * sin(t * speed + phase)
        }
        return [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(drift(0.5, 0.0, 0.31, 0.16), 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, drift(0.5, 1.7, 0.27, 0.16)),
            SIMD2<Float>(drift(0.5, 0.8, 0.35, 0.14), drift(0.5, 2.4, 0.29, 0.14)),
            SIMD2<Float>(1, drift(0.5, 3.1, 0.24, 0.16)),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(drift(0.5, 4.2, 0.28, 0.16), 1),
            SIMD2<Float>(1, 1)
        ]
    }
}
