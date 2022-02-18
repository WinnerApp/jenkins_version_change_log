// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "jenkins_version_change_log",
    platforms: [.macOS(.v10_12)],
    products: [
        .executable(name: "jvcl",
                    targets: ["jenkins_version_change_log"]
                   )
    ],
    dependencies: [
        .package(name: "SwiftShell",
                 url: "https://github.com/kareman/SwiftShell",
                 from: "5.1.0"
                ),
        .package(name: "swift-argument-parser",
                 url: "https://github.com/apple/swift-argument-parser",
                 from: "1.0.0"),
        .package(name: "SwiftyJSON",
                 url: "https://github.com/SwiftyJSON/SwiftyJSON.git",
                 from: "5.0.0"),
        .package(name: "Alamofire",
                 url: "https://github.com/Alamofire/Alamofire.git",
                 from: "5.5.0")
    ],
    targets: [
        .testTarget(
            name: "jenkins_version_change_logTests",
            dependencies: ["jenkins_version_change_log"]
        ),
        .executableTarget(
            name: "jenkins_version_change_log",
            dependencies: [
                "SwiftShell",
                .product(name: "ArgumentParser",
                         package: "swift-argument-parser"),
                "SwiftyJSON",
                "Alamofire"
            ]
        )
    ]
)
