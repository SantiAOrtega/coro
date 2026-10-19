// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoroKit",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [
        .library(name: "CoroKit", targets: ["CoroKit"])
    ],
    targets: [
        .target(name: "CoroKit"),
        .testTarget(name: "CoroKitTests", dependencies: ["CoroKit"])
    ]
)
