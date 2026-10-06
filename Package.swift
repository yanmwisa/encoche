// swift-tools-version:5.9
// Compilation sans Xcode : le projet Xcode d'origine reste la référence.
// Versions épinglées comme dans Package.resolved du projet Xcode.
import PackageDescription

let package = Package(
    name: "NotchDrop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/EmergeTools/Pow", exact: "1.0.6"),
        .package(url: "https://github.com/Lakr233/ColorfulX", exact: "5.7.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", exact: "1.1.0"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchDrop",
            dependencies: [
                .product(name: "Pow", package: "Pow"),
                .product(name: "ColorfulX", package: "ColorfulX"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            path: "NotchDrop",
            exclude: [
                "Assets.xcassets",
                "InfoPlist.xcstrings",
                "Localizable.xcstrings",
                "Info.plist",
                "NotchDrop.entitlements",
            ]
        ),
    ]
)
