// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LazyMouse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LazyMouse", targets: ["LazyMouse"]),
        .library(name: "LazyMouseCore", targets: ["LazyMouseCore"])
    ],
    targets: [
        .target(name: "LazyMouseCore"),
        .executableTarget(
            name: "LazyMouse",
            dependencies: ["LazyMouseCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(name: "LazyMouseCoreTests", dependencies: ["LazyMouseCore"])
    ]
)
