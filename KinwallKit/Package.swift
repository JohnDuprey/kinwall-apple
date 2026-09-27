// swift-tools-version: 6.0
// Shared core for the Kinwall iPhone, iPad and Apple Watch apps: the API client, models,
// device pairing and key storage. No UI, so it builds and tests on macOS with `swift test`.
import PackageDescription

let package = Package(
    name: "KinwallKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "KinwallKit", targets: ["KinwallKit"])],
    targets: [
        .target(name: "KinwallKit"),
        .testTarget(name: "KinwallKitTests", dependencies: ["KinwallKit"]),
    ]
)
