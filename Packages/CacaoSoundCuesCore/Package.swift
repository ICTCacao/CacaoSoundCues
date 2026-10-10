// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CacaoSoundCuesCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CacaoSoundCuesCore", targets: ["CacaoSoundCuesCore"]),
    ],
    targets: [
        .target(name: "CacaoSoundCuesCore"),
        .testTarget(name: "CacaoSoundCuesCoreTests", dependencies: ["CacaoSoundCuesCore"]),
    ]
)
