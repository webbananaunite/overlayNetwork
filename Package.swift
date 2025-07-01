// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(Linux)
/*
 as Build on macOS. in 20250530

 //
 //download & install Swifty tool chain & Static linux sdk
 //
 $ curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && ~/.swiftly/bin/swiftly init --quiet-shell-followup && . ${SWIFTLY_HOME_DIR:-~/.swiftly}/env.sh && hash -r
 $ download Static Linux SDK https://www.swift.org/install/macos/
 $ xattr -d -r -s com.apple.quarantine "{Downloads dir}/swift-6.1.2-RELEASE_static-linux-0.0.1.artifactbundle.tar"
 $ swift sdk install {Downloads dir}/swift-6.1.2-RELEASE_static-linux-0.0.1.artifactbundle.tar --checksum df0b40b9b582598e7e3d70c82ab503fd6fbfdff71fd17e7f1ab37115a0665b3b
 //
 //cross compile for Linux
 //
 $ cd {Project Directory}
 $ TOOLCHAINS=org.swift.612202505261a swift build -v --swift-sdk x86_64-swift-linux-musl --build-path {App Output Path}/Testy
 */
let includePath = "/Users/yoichi/Library/org.swift.swiftpm/swift-sdks/swift-6.1.2-RELEASE_static-linux-0.0.1.artifactbundle/swift-6.1.2-RELEASE_static-linux-0.0.1/swift-linux-musl/musl-1.2.5.sdk/x86_64/usr/include"
#else
#endif
var productsSettings: [PackageDescription.Product] = []
var dependenciesSettings: [Package.Dependency] = []
var cSettings: [CSetting] = []
var cSettingsForResolving: [CSetting] = []
var swiftSettings: [SwiftSetting] = []
var linkerSettings: [LinkerSetting] = []

productsSettings = [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
        name: "overlayNetwork",
        targets: ["overlayNetwork"]
    ),
    .library(
        name: "Resolving",
        targets: ["Resolving"]
    )
]
dependenciesSettings = [
    //using as import Crypto
    .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.4.0")),
]
/*
 os() Preprocessor represent build environment OS in Package.swift Manifest.
 */
#if os(Linux)
/*
 as Build on Linux.
 */
cSettings = [
    .unsafeFlags(["-I" + includePath]),
    .unsafeFlags(["-fmodule-map-file=Sources/module.modulemap"])
]
swiftSettings = [
    .unsafeFlags(["-I" + includePath]),
]
linkerSettings = [
    .linkedLibrary("c++"),
]
#else
/*
 as Build iOS library on macOS.
 Xcode Build
 
 or
 as Linux Cross-Compile on macOS.

 $ cd {Project Directory}
 $ TOOLCHAINS=org.swift.600202407161a swift build -v --swift-sdk x86_64-swift-linux-musl --build-path {App Output Path}/overlayNetwork
 */
linkerSettings = [
    .linkedLibrary("c++"),
    .linkedLibrary("resolv")
]
#endif
let package = Package(
    name: "overlayNetwork",
    /*
     as Swift version check on Xcode Build.
     */
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16),
    ],
    products: productsSettings,
    dependencies: dependenciesSettings,
    targets: [
        .target(
            name: "overlayNetwork",
            dependencies: [
                .target(name: "Resolving"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/overlayNetwork",
//            publicHeadersPath: "Sources/Resolving/include",
            cSettings: cSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        ),
        .target(
            name: "Resolving",
            path: "Sources/Resolving",
//            publicHeadersPath: "./include",
            cSettings: cSettingsForResolving,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings
        ),
        .testTarget(
            name: "overlayNetworkTests",
            dependencies: [
                "overlayNetwork"
            ],
            path: "Tests/overlayNetworkTests",
            linkerSettings: linkerSettings
        )
    ]
)
