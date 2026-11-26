// swift-tools-version:5.5

import PackageDescription

let core = "../../../core-xprojects"

let package = Package(
    name: "DecodeBench",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../packages/TGUIKit"),
        .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "FFMpegBinding", path: "../../../submodules/telegram-ios/submodules/FFMpegBinding"),
        .package(name: "YuvConversion", path: "../../../submodules/telegram-ios/submodules/YuvConversion"),
    ],
    targets: [
        .executableTarget(
            name: "DecodeBench",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "FFMpegBinding", package: "FFMpegBinding", condition: nil),
                .product(name: "YuvConversion", package: "YuvConversion", condition: nil),
            ],
            path: "Sources/DecodeBench",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(core)/ffmpeg/build/ffmpeg/lib",
                    "-L\(core)/libvpx/build/libvpx/lib",
                    "-L\(core)/libopus/build/libopus/lib",
                    "-L\(core)/dav1d/build/dav1d/lib",
                    "-lavformat", "-lavcodec", "-lswresample", "-lavutil", "-lvpx", "-lopus", "-ldav1d",
                    "-lz", "-lbz2", "-liconv",
                ]),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreImage"),
                .linkedFramework("AVFoundation"),
            ]),
    ]
)
