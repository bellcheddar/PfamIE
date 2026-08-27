import PfamIEKit
import RealityKit
import SwiftUI

/// The Pfam universe at room scale.
///
/// The volume is a box on a table you lean into; the immersive space puts the
/// map around you and lets you walk through it. Same batched per-clan meshes as
/// the volume, because 30,031 individual entities is not a frame rate at any
/// scale, just spread over a few metres instead of a few centimetres.
///
/// Mixed immersion rather than full: this is a scientific instrument, and being
/// able to see the desk and the person you are talking to is the point.
struct ImmersiveGalaxy: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    @State private var built = false

    private var theme: Theme { Theme.resolve(scheme) }

    /// Metres. The cloud spans about three metres, centred a little above eye
    /// level and pushed back so it does not open inside the viewer.
    private static let extent: Float = 1.5
    private static let pointRadius: Float = 0.009
    private static let centre = SIMD3<Float>(0, 1.4, -1.8)

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "immersive-galaxy"
            root.position = Self.centre
            content.add(root)
        } update: { content in
            guard !built, app.state.isReady, let root = content.entities.first else { return }
            built = true
            populate(root)
        }
    }

    private func populate(_ root: Entity) {
        var buckets: [String: [Family]] = [:]
        for family in app.families {
            buckets[family.clan?.rawValue ?? "-", default: []].append(family)
        }

        for (key, families) in buckets {
            guard let mesh = Self.mesh(for: families) else { continue }
            let colour = app.clanColour(for: families[0], theme: theme)
            var material = UnlitMaterial(color: UIColor(colour))
            material.blending = .transparent(
                opacity: .init(floatLiteral: key == "-" ? 0.35 : 0.9)
            )
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "immersive-clan-\(key)"
            root.addChild(entity)
        }
    }

    private static func mesh(for families: [Family]) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        positions.reserveCapacity(families.count * 4)
        triangles.reserveCapacity(families.count * 12)

        let corners: [SIMD3<Float>] = [
            SIMD3(0, 1, 0), SIMD3(0.943, -0.333, 0),
            SIMD3(-0.471, -0.333, 0.816), SIMD3(-0.471, -0.333, -0.816),
        ]
        let faces: [(Int, Int, Int)] = [(0, 1, 2), (0, 2, 3), (0, 3, 1), (1, 3, 2)]

        for family in families {
            let position = family.position * extent
            let base = UInt32(positions.count)
            for corner in corners {
                positions.append(position + corner * pointRadius)
            }
            for (a, b, c) in faces {
                triangles.append(contentsOf: [base + UInt32(a), base + UInt32(b), base + UInt32(c)])
            }
        }
        guard !positions.isEmpty else { return nil }

        var descriptor = MeshDescriptor(name: "families")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(triangles)
        return try? MeshResource.generate(from: [descriptor])
    }
}
