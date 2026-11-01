// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bd-reminders",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "bd-reminders",
            targets: ["bd-reminders"]
        ),
        .library(
            name: "BdRemindersCore",
            targets: ["BdRemindersCore"]
        )
    ],
    targets: [
        .target(
            name: "BdRemindersCore",
            dependencies: [],
            path: "Sources/BdRemindersCore"
        ),
        .executableTarget(
            name: "bd-reminders",
            dependencies: ["BdRemindersCore"],
            path: "Sources/bd-reminders"
        ),
        .testTarget(
            name: "BdRemindersCoreTests",
            dependencies: ["BdRemindersCore"],
            path: "Tests/BdRemindersCoreTests"
        )
    ]
)
