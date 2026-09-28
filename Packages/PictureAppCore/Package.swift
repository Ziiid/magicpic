// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PictureAppCore",
    defaultLocalization: "sv",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PictureAppCore", targets: ["PictureAppCore"])
    ],
    targets: [
        .target(
            name: "PictureAppCore",
            path: "Sources/PictureAppCore",
            resources: [.process("Localizable.xcstrings")]
        )
    ]
)
