// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClassNoteCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ClassNoteCore", targets: ["ClassNoteCore"])],
    targets: [
        .target(name: "ClassNoteCore"),
        .testTarget(name: "ClassNoteCoreTests", dependencies: ["ClassNoteCore"])
    ]
)
