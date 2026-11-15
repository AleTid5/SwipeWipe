// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwipeWipeCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SwipeWipeCore", targets: ["SwipeWipeCore"])
    ],
    targets: [
        .target(
            name: "SwipeWipeCore",
            path: "SwipeWipe",
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "DuplicatesView.swift",
                "PhotoLibraryService.swift",
                "PhotoThumbnail.swift",
                "QueueView.swift",
                "ReviewView.swift",
                "SettingsView.swift",
                "SwipeWipeApp.swift",
                "SwipeWipeModel.swift"
            ],
            sources: ["ReviewActionHistory.swift"]
        ),
        .testTarget(
            name: "SwipeWipeCoreTests",
            dependencies: ["SwipeWipeCore"],
            path: "Tests/SwipeWipeCoreTests"
        )
    ]
)
