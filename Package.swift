// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Meditor",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Meditor", targets: ["Meditor"])
    ],
    targets: [
        .executableTarget(
            name: "Meditor",
            path: "Sources/Meditor",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MeditorTests",
            dependencies: ["Meditor"],
            path: "Tests/MeditorTests"
        )
    ]
)
