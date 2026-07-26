// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "betterGI-mac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "betterGI-mac", targets: ["MacGI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacGIShims",
            path: "Sources/MacGIShims",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacGI",
            dependencies: ["MacGIShims"],
            path: "Sources/MacGI",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
            ]
        ),
        .testTarget(
            name: "MacGITests",
            dependencies: ["MacGI"],
            path: "Tests/MacGITests"
        )
    ]
)
