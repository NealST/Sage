// swift-tools-version: 5.9
//
// Modified for Sage: this vendored manifest intentionally exposes only the
// dependency-free core target. Optional upstream adapter targets are omitted
// so Sage can build the editor without resolving remote packages.

import PackageDescription

let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
    ],
    targets: [
        .target(name: "MarkdownEngine"),
        .testTarget(
            name: "MarkdownEngineTests",
            dependencies: ["MarkdownEngine"]
        ),
    ]
)
