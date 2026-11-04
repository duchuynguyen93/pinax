// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pinax",
    platforms: [.macOS("26.0")],
    targets: [
        // Lõi logic: không UI, test được bằng thư mục tạm.
        .target(name: "PinaxCore"),
        .executableTarget(name: "Pinax", dependencies: ["PinaxCore"]),
        .testTarget(name: "PinaxCoreTests", dependencies: ["PinaxCore"]),
    ],
    swiftLanguageModes: [.v5]
)
