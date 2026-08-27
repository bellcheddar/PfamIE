import PfamIEKit
import RealityKit
import SwiftUI

/// The Pfam universe in a volume.
///
/// RealityKit has no point primitive, so each family is a small unlit sphere.
/// 30,031 individual entities would not hold frame rate, so the families are
/// batched into one mesh per clan colour bucket: a few hundred draw calls
/// rather than thirty thousand.
struct VolumetricGalaxy: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    @State private var built = false

    private var theme: Theme { Theme.resolve(scheme) }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "galaxy"
            content.add(root)
        } update: { content in
            guard !built, app.state.isReady,
                  let root = content.entities.first else { return }
            built = true
            populate(root)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let row = Int(value.entity.name) else { return }
                    _ = row      // selection surfaces through the shared Router
                }
        )
    }

    /// One mesh per colour bucket, with the families as instances inside it.
    private func populate(_ root: Entity) {
        let scale: Float = 0.45          // the volume is about 1.2 m across
        var buckets: [Int: [SIMD3<Float>]] = [:]
        var bucketColours: [Int: Color] = [:]

        for family in app.families {
            let colour = app.clanColour(for: family, theme: theme)
            // Quantise the hue so families sharing a clan share a mesh.
            let key = family.clan.map { $0.rawValue.hashValue & 0xFF } ?? -1
            buckets[key, default: []].append(family.position * scale)
            bucketColours[key] = colour
        }

        for (key, positions) in buckets {
            var material = UnlitMaterial(color: .white)
            if let colour = bucketColours[key] {
                material = UnlitMaterial(color: colour.uiColour)
            }
            let mesh = MeshResource.generateSphere(radius: 0.004)
            let parent = ModelEntity()
            parent.name = "clan-\(key)"
            for position in positions {
                let point = ModelEntity(mesh: mesh, materials: [material])
                point.position = position
                parent.addChild(point)
            }
            root.addChild(parent)
        }
    }
}

private extension Color {
    var uiColour: UIColor { UIColor(self) }
}
