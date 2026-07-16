// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MySQLMacClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MySQLMacClient", targets: ["MySQLMacClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MySQLMacClient",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio")
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "MySQLMacClientTests",
            dependencies: ["MySQLMacClient"]
        )
    ]
)
