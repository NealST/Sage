// swift-tools-version:5.9
import PackageDescription

// Local fork of upstream Package.swift: always include scanner.c.
// Upstream uses FileManager at package-load time, which fails under Xcode SPM
// when the process CWD is not the package root, causing undefined scanner symbols.

let package = Package(
    name: "TreeSitterPython",
    products: [
        .library(name: "TreeSitterPython", targets: ["TreeSitterPython"]),
    ],
    targets: [
        .target(
            name: "TreeSitterPython",
            path: ".",
            sources: [
                "src/parser.c",
                "src/scanner.c",
            ],
            resources: [
                .copy("queries")
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
    ],
    cLanguageStandard: .c11
)
