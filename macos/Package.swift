// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusOn",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FocusOn", targets: ["FocusOn"]),
               .executable(name: "FocusGazeDebug", targets: ["FocusGazeDebug"])],
    targets: [
        .target(name: "FocusCore"),
        .target(name: "FocusVision", dependencies: ["FocusCore"]),
        .executableTarget(name: "FocusOn", dependencies: ["FocusCore", "FocusVision"],
                          exclude: ["Resources/phase-pet.png"],
                          resources: [.copy("Resources/phase-peek.png")]),
        .executableTarget(name: "FocusGazeDebug", dependencies: ["FocusCore", "FocusVision"]),
        .executableTarget(name: "FocusCoreChecks", dependencies: ["FocusCore"], path: "Tests/FocusCoreTests")
    ]
)
