// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XcodeprojToJson",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/ProjectAutomation", from: "3.0.0"),
        .package(url: "https://github.com/phimage/XcodeProjKit.git", from: "3.0.0"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-package-manager.git", branch: "main"),
        .package(path: "../SwiftPrettyPrint"),
//        .package(url: "https://github.com/HaiFengKao/SwiftPrettyPrint.git", .upToNextMajor(from: "1.2.0")),
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "XcodeprojToJson",
            dependencies: ["XcodeProjKit", "Files", "ProjectAutomation", .product(name: "PackageDescription", package: "swift-package-manager"), "SwiftPrettyPrint"],

            // magic from https://forums.swift.org/t/leveraging-availability-for-packagedescription-apis/18667
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
            ]
        ),
        .testTarget(
            name: "XcodeprojToJsonTests",
            dependencies: ["XcodeprojToJson"]
        ),
    ]
)
