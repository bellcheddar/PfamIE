// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PfamIEKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "PfamIEKit", targets: ["PfamIEKit"]),
    ],
    targets: [
        .target(
            name: "PfamIEKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PfamIEKitTests",
            dependencies: ["PfamIEKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
