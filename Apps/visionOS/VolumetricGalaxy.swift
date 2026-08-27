import PfamIEKit
import RealityKit
import SwiftUI

/// The Pfam universe in a volume you can walk around.
///
/// RealityKit has no point primitive, so each family is drawn as a small
/// tetrahedron. The naive version of this made one `ModelEntity` per family:
/// 30,031 entities, 30,031 draw calls, and a scene that never reaches frame
/// rate. Instead the families are batched into one generated mesh per clan,
/// which is 892 meshes at worst and typically far fewer on screen at once.
///
/// Tetrahedra rather than quads because the viewer walks around the volume: a
/// flat billboard would need reorienting every frame, and would vanish
/// edge-on when it was not.
struct VolumetricGalaxy: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    @State private var built = false
    @State private var selection: Family?

    private var theme: Theme { Theme.resolve(scheme) }

    /// Metres. The default volume is 1.2 m on a side, so the cloud is sized to
    /// sit inside it with room to lean in.
    private static let extent: Float = 0.45
    private static let pointRadius: Float = 0.0035

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "galaxy"
            content.add(root)
        } update: { content in
            guard !built, app.state.isReady, let root = content.entities.first else { return }
            built = true
            populate(root)
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            if let selection {
                selectionCard(selection)
            } else {
                Text("\(app.families.count.formatted()) Pfam families")
                    .font(.caption)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassBackgroundEffect()
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // The tapped entity is a clan batch, so resolve the family
                    // from the tap location rather than from the entity.
                    let local = value.entity.convert(
                        position: value.location3D.simd, from: nil
                    )
                    selection = nearestFamily(to: local)
                }
        )
    }

    private func selectionCard(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(family.displayName)
                .font(.system(.headline, design: .rounded))
            Text(family.summary)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Text(family.accession.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .glassBackgroundEffect()
    }

    private func nearestFamily(to point: SIMD3<Float>) -> Family? {
        var best: Family?
        var bestDistance = Float.greatestFiniteMagnitude
        for family in app.families {
            let d = simd_distance_squared(family.position * Self.extent, point)
            if d < bestDistance { bestDistance = d; best = family }
        }
        // Only accept a tap that actually landed near a family.
        return bestDistance < 0.02 * 0.02 ? best : nil
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
            material.blending = .transparent(opacity: .init(floatLiteral: key == "-" ? 0.45 : 1.0))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "clan-\(key)"
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [
                .generateBox(size: SIMD3<Float>(repeating: Self.extent * 2.2))
            ]))
            root.addChild(entity)
        }
    }

    /// One mesh holding a tetrahedron per family.
    private static func mesh(for families: [Family]) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        positions.reserveCapacity(families.count * 4)
        triangles.reserveCapacity(families.count * 12)

        // Unit tetrahedron, scaled per point.
        let corners: [SIMD3<Float>] = [
            SIMD3(0, 1, 0), SIMD3(0.943, -0.333, 0),
            SIMD3(-0.471, -0.333, 0.816), SIMD3(-0.471, -0.333, -0.816),
        ]
        let faces: [(Int, Int, Int)] = [(0, 1, 2), (0, 2, 3), (0, 3, 1), (1, 3, 2)]

        for family in families {
            let centre = family.position * extent
            let base = UInt32(positions.count)
            for corner in corners {
                positions.append(centre + corner * pointRadius)
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

private extension Point3D {
    var simd: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
