import SwiftUI

enum HiveMarkGeometry {
    static let cellCount = 7

    private static let offsets: [SIMD2<Double>] = [
        SIMD2(0, 0), SIMD2(-1.9, 0), SIMD2(1.9, 0),
        SIMD2(-0.95, -1.65), SIMD2(0.95, -1.65),
        SIMD2(-0.95, 1.65), SIMD2(0.95, 1.65)
    ]

    static func cell(_ index: Int, in rect: CGRect) -> Path {
        guard offsets.indices.contains(index) else { return Path() }
        let cellRadius = min(rect.width, rect.height) * 0.155
        let offset = offsets[index]
        let cellCenter = CGPoint(
            x: rect.midX + offset.x * cellRadius,
            y: rect.midY + offset.y * cellRadius
        )
        let points = (0..<6).map { corner -> CGPoint in
            let angle = Angle.degrees(-90 + 60 * Double(corner)).radians
            return CGPoint(
                x: cellCenter.x + cellRadius * cos(angle),
                y: cellCenter.y + cellRadius * sin(angle)
            )
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// A compact cluster of seven honeycomb cells with even gutters.
struct HiveMark: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<HiveMarkGeometry.cellCount {
            path.addPath(HiveMarkGeometry.cell(index, in: rect))
        }
        return path
    }
}

/// One honeycomb cell of the mark, positioned within the full mark's frame.
struct HiveMarkCell: Shape {
    let index: Int

    nonisolated func path(in rect: CGRect) -> Path {
        HiveMarkGeometry.cell(index, in: rect)
    }
}
