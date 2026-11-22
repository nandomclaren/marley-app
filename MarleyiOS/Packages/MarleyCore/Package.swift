// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MarleyCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "MarleyCore", targets: ["MarleyCore"])],
    targets: [
        .target(name: "MarleyCore"),
        .testTarget(name: "MarleyCoreTests", dependencies: ["MarleyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
