// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PictureApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PictureApp",
            path: "Sources/PictureApp",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                // Embed Info.plist directly into the executable so macOS shows the
                // proper Photos-access permission prompt (with our usage description)
                // even when running via `swift run`, not only from a bundled .app.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PictureApp/Resources/Info.plist"
                ])
            ]
        )
    ]
)
