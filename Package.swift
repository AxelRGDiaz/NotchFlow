// swift-tools-version: 6.0
import PackageDescription

// Los nombres de módulo son neutros (NotchKit, NotchApp) a propósito: el nombre
// comercial vive en Config/app.env y puede cambiarse sin renombrar código.
let package = Package(
    name: "NotchFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchApp", targets: ["NotchApp"]),
        .library(name: "NotchKit", targets: ["NotchKit"]),
    ],
    targets: [
        .executableTarget(name: "NotchApp", dependencies: ["NotchKit"], path: "App"),
        .target(name: "NotchKit", path: "Sources/NotchKit"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"], path: "Tests/NotchKitTests"),
    ]
)
