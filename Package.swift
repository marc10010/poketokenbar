// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PokeTokenBar", targets: ["PokeTokenBar"]),
        .executable(name: "PokeTokenBarSelfTest", targets: ["PokeTokenBarSelfTest"]),
        .library(name: "PokeTokenBarCore", targets: ["PokeTokenBarCore"]),
    ],
    targets: [
        .target(
            name: "PokeTokenBarCore",
            resources: [.process("Resources/pokedex.json"), .process("Resources/typechart.json")]
        ),
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: ["PokeTokenBarCore"]
        ),
        // Arnés propio en vez de .testTarget: XCTest requiere Xcode completo
        // y esto corre con solo las Command Line Tools.
        .executableTarget(
            name: "PokeTokenBarSelfTest",
            dependencies: ["PokeTokenBarCore"]
        ),
    ]
)
