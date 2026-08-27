import SwiftUI

#if canImport(SceneKit) && !os(visionOS) && !os(watchOS)
import SceneKit

/// The Pfam universe as a SceneKit point cloud.
///
/// One geometry holding all 30,031 points, not 30,031 nodes: a node each would
/// cost a draw call each and never hold 60 fps. Colour is per-vertex (clan hue)
/// and size scales with the log of family size.
struct SceneKitGalaxy: PlatformViewRepresentable {

    let points: [GalaxyModel.Point]
    let theme: Theme
    let focusRow: Int?
    let cometPosition: SIMD3<Float>?
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject {
        let onSelect: (Int) -> Void
        var builtForDarkTheme: Bool?
        var positions: [SIMD3<Float>] = []
        var cameraNode: SCNNode?
        var cometNode: SCNNode?
        var selectionNode: SCNNode?
        var lastFocus: Int?
        weak var view: SCNView?

        init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }

        /// Point clouds do not hit-test usefully, so find the nearest point in
        /// screen space instead. Projecting 30,031 points costs about a
        /// millisecond and is exact, where a ray tolerance is a guess.
        @objc func handleTap(_ recogniser: PlatformGestureRecognizer) {
            guard let view, !positions.isEmpty else { return }
            let location = recogniser.location(in: view)
            var bestIndex = -1
            var bestDistance = CGFloat.greatestFiniteMagnitude

            for (index, position) in positions.enumerated() {
                let projected = view.projectPoint(
                    SCNVector3(position.x, position.y, position.z)
                )
                // Behind the camera.
                if projected.z < 0 || projected.z > 1 { continue }
                let dx = CGFloat(projected.x) - location.x
                let dy = CGFloat(projected.y) - location.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            // 44 points is roughly a fingertip; beyond that the tap was on
            // empty sky and selecting the nearest star would feel arbitrary.
            if bestIndex >= 0 && bestDistance < 44 * 44 {
                onSelect(bestIndex)
            }
        }
    }

    func makePlatformView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling2X
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 60

        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.01
        camera.zFar = 200
        // A little bloom is what makes a point cloud read as a starfield
        // rather than as scatter-plot dots.
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 0.62
        camera.bloomBlurRadius = 5

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2.6)
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        context.coordinator.cameraNode = cameraNode
        context.coordinator.view = view

        let tap = PlatformGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updatePlatformView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }

        if context.coordinator.positions.count != points.count
            || context.coordinator.builtForDarkTheme != theme.isDark {
            context.coordinator.builtForDarkTheme = theme.isDark
            context.coordinator.positions = points.map(\.position)
            scene.rootNode.childNodes
                .filter { $0.name == "cloud" }
                .forEach { $0.removeFromParentNode() }
            let cloud = SCNNode(geometry: makeGeometry())
            cloud.name = "cloud"
            // A slow drift keeps it alive without demanding attention. Reduce
            // Motion is respected by the caller, which passes no animation.
            cloud.runAction(.repeatForever(
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 240)
            ))
            scene.rootNode.addChildNode(cloud)
        }

        updateComet(in: scene, context: context)
        if let focusRow, focusRow != context.coordinator.lastFocus {
            context.coordinator.lastFocus = focusRow
            flyTo(row: focusRow, view: view, context: context)
        }
    }

    private func makeGeometry() -> SCNGeometry {
        var positions: [SCNVector3] = []
        var colours: [SIMD4<Float>] = []
        positions.reserveCapacity(points.count)
        colours.reserveCapacity(points.count)

        // Additive blending sums every overlapping point, and 30,031 points in
        // a UMAP have a very dense core. At full intensity that core saturates
        // to flat white and every clan colour in the middle of the map is lost,
        // which is the one thing the Galaxy exists to show. Damping each point
        // lets ten or twenty overlap before they reach white, so density reads
        // as brightness and the hue survives.
        let intensity: Float = theme.isDark ? 0.22 : 1.0

        for point in points {
            positions.append(SCNVector3(point.position.x, point.position.y, point.position.z))
            // Unknown families are drawn dim rather than a different hue: the
            // dark proteome should read as unlit sky, not as another clan.
            let alpha: Float = point.isDUF ? 0.45 : 1.0
            colours.append(SIMD4<Float>(
                point.colour.x * intensity,
                point.colour.y * intensity,
                point.colour.z * intensity,
                alpha
            ))
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let colourData = Data(bytes: colours, count: colours.count * MemoryLayout<SIMD4<Float>>.size)
        let colourSource = SCNGeometrySource(
            data: colourData,
            semantic: .color,
            vectorCount: colours.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.size
        )

        var indices = Array(UInt32(0)..<UInt32(points.count))
        let element = SCNGeometryElement(
            data: Data(bytes: &indices, count: indices.count * MemoryLayout<UInt32>.size),
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 3.5

        let geometry = SCNGeometry(sources: [positionSource, colourSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        // Additive blending is what makes a dark starfield glow, and it is
        // exactly wrong on a light ground: every overlap drives towards white
        // until the dense centre of the map is a featureless blob. Light mode
        // blends normally, so dense regions go darker rather than brighter.
        material.blendMode = theme.isDark ? .add : .alpha
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    private func updateComet(in scene: SCNScene, context: Context) {
        context.coordinator.cometNode?.removeFromParentNode()
        context.coordinator.cometNode = nil
        guard let cometPosition else { return }

        let sphere = SCNSphere(radius: 0.035)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = theme.accentFlare.platformColour
        material.emission.contents = theme.accentFlare.platformColour
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(cometPosition.x, cometPosition.y, cometPosition.z)
        node.runAction(.repeatForever(.sequence([
            .scale(to: 1.35, duration: 0.9),
            .scale(to: 1.0, duration: 0.9),
        ])))
        scene.rootNode.addChildNode(node)
        context.coordinator.cometNode = node
    }

    private func flyTo(row: Int, view: SCNView, context: Context) {
        guard row >= 0, row < points.count, let camera = context.coordinator.cameraNode else { return }
        let target = points[row].position
        // Stop short of the point rather than inside it, along the line from
        // the origin, so the family sits centred with its neighbourhood behind.
        let direction = simd_normalize(target == .zero ? SIMD3<Float>(0, 0, 1) : target)
        let destination = target + direction * 0.55

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.9
        camera.position = SCNVector3(destination.x, destination.y, destination.z)
        camera.look(at: SCNVector3(target.x, target.y, target.z))
        SCNTransaction.commit()
    }
}

#if canImport(UIKit)
typealias PlatformGestureRecognizer = UITapGestureRecognizer
#else
typealias PlatformGestureRecognizer = NSClickGestureRecognizer
#endif

extension Color {
    var platformColour: Any {
        #if canImport(UIKit)
        return UIColor(self)
        #else
        return NSColor(self)
        #endif
    }
}

#endif
