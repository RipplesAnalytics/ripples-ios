// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Ripples",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "Ripples", targets: ["Ripples"]),
    ],
    targets: [
        .target(name: "Ripples", path: "Sources/Ripples"),
        .testTarget(name: "RipplesTests", dependencies: ["Ripples"], path: "Tests/RipplesTests"),
    ]
)
