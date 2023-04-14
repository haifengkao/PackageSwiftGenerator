// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PackageSwiftGenerator",
    platforms: [
        .macOS("13.0"),
    ],
    products: [
        .executable(name: "tuist-generate-package-swift", targets: ["PackageSwiftGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/ProjectAutomation", from: "3.0.0"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-package-manager", branch: "release/5.7"),
//        .package(path: "../SwiftPrettyPrint"),
        .package(url: "https://github.com/HaiFengKao/SwiftPrettyPrint.git", .upToNextMajor(from: "1.4.0")),
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "PackageSwiftGenerator",

            dependencies: ["Files",
                           "ProjectAutomation",
                           .product(name: "PackageDescription", package: "swift-package-manager"),
                           "SwiftPrettyPrint",
                           .product(name: "ArgumentParser", package: "swift-argument-parser")],

            // magic from https://forums.swift.org/t/leveraging-availability-for-packagedescription-apis/18667
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
            ],
            // need libPackageDescription.dylib from Xcode
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI/"])]
        ),
        .testTarget(
            name: "PackageSwiftGeneratorTests",
            dependencies: ["PackageSwiftGenerator"]
        ),
    ]
)
