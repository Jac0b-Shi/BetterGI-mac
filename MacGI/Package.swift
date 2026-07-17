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
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2")
    ],
    targets: [
        .executableTarget(
            name: "MacGI",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ],
            path: "Sources/MacGI",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .testTarget(
            name: "MacGITests",
            dependencies: ["MacGI"],
            path: "Tests/MacGITests"
        )
    ]
)
