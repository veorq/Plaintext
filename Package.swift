// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plaintext",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Plaintext", targets: ["Plaintext"])
    ],
    targets: [
        .executableTarget(
            name: "Plaintext",
            path: "Sources/Plaintext"
        )
    ]
)
