// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LEDctrl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LEDctrl", targets: ["LEDctrl"]),
        .executable(name: "LEDProbe", targets: ["LEDProbe"]),
        .executable(name: "LEDSerialProbe", targets: ["LEDSerialProbe"]),
        .executable(name: "LEDSerialConfigUpload", targets: ["LEDSerialConfigUpload"]),
        .executable(name: "LEDConfigPatch", targets: ["LEDConfigPatch"]),
        .executable(name: "LEDConfigUpload", targets: ["LEDConfigUpload"]),
        .executable(name: "LEDSigmaSend", targets: ["LEDSigmaSend"]),
        .executable(name: "LEDNmgSend", targets: ["LEDNmgSend"]),
        .executable(name: "LEDPixelSend", targets: ["LEDPixelSend"]),
        .executable(name: "LEDFirmwareDump", targets: ["LEDFirmwareDump"]),
        .executable(name: "LEDPngSequenceSend", targets: ["LEDPngSequenceSend"])
    ],
    targets: [
        .target(name: "SigmaProtocol"),
        .executableTarget(
            name: "LEDctrl",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(name: "LEDProbe"),
        .executableTarget(name: "LEDSerialProbe"),
        .executableTarget(name: "LEDSerialConfigUpload"),
        .executableTarget(name: "LEDConfigPatch"),
        .executableTarget(
            name: "LEDConfigUpload",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(
            name: "LEDSigmaSend",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(
            name: "LEDNmgSend",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(
            name: "LEDPixelSend",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(
            name: "LEDFirmwareDump",
            dependencies: ["SigmaProtocol"]
        ),
        .executableTarget(
            name: "LEDPngSequenceSend",
            dependencies: ["SigmaProtocol"]
        )
    ]
)
