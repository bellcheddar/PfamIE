import SwiftUI

/// What every Galaxy renderer is handed, and what it must be able to do.
///
/// Three platforms draw this map three ways: SceneKit on iOS, iPadOS and
/// macOS, a RealityKit volume on visionOS, and a static snapshot on watchOS.
/// Abstracting the seam from the start is the difference between a
/// multiplatform app and an iOS app with three ports.
public protocol GalaxyRenderer {
    /// Move the camera to a family and select it.
    func focus(row: Int, animated: Bool)
    /// Place or move the query comet, or remove it when nil.
    func setComet(position: SIMD3<Float>?)
}

/// The point cloud, prepared once and shared by every renderer.
@MainActor
@Observable
public final class GalaxyModel {

    public struct Point: Sendable {
        public let row: Int
        public let position: SIMD3<Float>
        public let colour: SIMD3<Float>
        /// Log-scaled by family size, so a 300,000-protein family reads as
        /// bigger than a 12-protein one without swamping the map.
        public let radius: Float
        public let isDUF: Bool
    }

    public private(set) var points: [Point] = []
    public var selection: Family?
    /// Where the last Oracle result sits, placed among its nearest families.
    public var cometPosition: SIMD3<Float>?
    public var visibleClans: Set<ClanID> = []
    public var showsDUFsOnly = false

    public init() {}

    public func build(from app: AppEnvironment, theme: Theme) {
        points = app.families.map { family in
            let colour = app.clanColour(for: family, theme: theme).rgbComponents
            let size = Float(max(family.proteinCount, 1))
            return Point(
                row: family.row,
                position: family.position,
                colour: colour,
                radius: 0.6 + log10(size) * 0.55,
                isDUF: family.isDUF
            )
        }
    }

    /// Places a query in the map from its nearest families.
    ///
    /// A parametric UMAP transform would put the query exactly where it
    /// belongs, but UMAP's inverse is not something to ship in an app. The
    /// weighted centroid of its top neighbours is honest for what it is: the
    /// comet lands among the families the query resembles, which is the only
    /// claim the Galaxy makes for it.
    public func cometPosition(
        for neighbours: [CentroidIndex.Neighbour],
        families: [Family]
    ) -> SIMD3<Float>? {
        let byRow = Dictionary(uniqueKeysWithValues: families.map { ($0.row, $0) })
        var total: Float = 0
        var accumulator = SIMD3<Float>(repeating: 0)
        for neighbour in neighbours.prefix(5) {
            guard let family = byRow[neighbour.row] else { continue }
            let weight = max(neighbour.probability, 0.001)
            accumulator += family.position * weight
            total += weight
        }
        guard total > 0 else { return nil }
        return accumulator / total
    }
}

extension Color {
    /// sRGB components, for handing a SwiftUI colour to a renderer.
    var rgbComponents: SIMD3<Float> {
        #if canImport(UIKit) && !os(watchOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
        #elseif canImport(AppKit)
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return SIMD3<Float>(Float(resolved.redComponent),
                            Float(resolved.greenComponent),
                            Float(resolved.blueComponent))
        #else
        return SIMD3<Float>(0.5, 0.8, 0.8)
        #endif
    }
}
