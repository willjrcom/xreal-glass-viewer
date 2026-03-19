// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PrismaXR",
    products: [
        .executable(name: "PrismaXR", targets: ["PrismaXRApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PrismaXRCapture",
            path: "Sources/PrismaXRCapture"),
        .target(
            name: "PrismaXRRenderer",
            path: "Sources/PrismaXRRenderer",
            resources: [
                .process("Shaders.metal")
            ]),
        .target(
            name: "PrismaXRTracking",
            path: "Sources/PrismaXRTracking"),
        .target(
            name: "PrismaXRVirtualDisplay",
            path: "Sources/PrismaXRVirtualDisplay"),
        .target(
            name: "PrismaXRLayout",
            dependencies: [
                "PrismaXRCapture",
                "PrismaXRTracking"
            ],
            path: "Sources/PrismaXRLayout"),
        .executableTarget(
            name: "PrismaXRApp",
            dependencies: [
                "PrismaXRCapture",
                "PrismaXRRenderer",
                "PrismaXRTracking",
                "PrismaXRLayout",
                "PrismaXRVirtualDisplay"
            ],
            path: "Sources/PrismaXRApp")
    ]
)
