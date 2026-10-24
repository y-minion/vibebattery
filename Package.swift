// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VibeBattery", platforms: [.macOS("15.0")], products: [
    .executable(name: "VibeBattery", targets: ["VibeBattery"]),
    .executable(name: "vbctl", targets: ["VibeCLI"]),
    .executable(name: "VBChargeHelper", targets: ["VBChargeHelper"]),
    .library(name: "BatteryCore", targets: ["BatteryCore"]),
    .library(name: "BatteryPlatform", targets: ["BatteryPlatform"]),
    .library(name: "MacBridge", targets: ["MacBridge"])
], targets: [
    .target(name: "BatteryCore"),
    .target(name: "MacBridge", linkerSettings: [.linkedLibrary("proc"), .linkedFramework("Foundation")]),
    .target(name: "BatteryPlatform", dependencies: ["BatteryCore", "MacBridge"], linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "VibeBattery", dependencies: ["BatteryCore", "BatteryPlatform"]),
    .executableTarget(name: "VibeCLI", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"]),
    .executableTarget(name: "VBChargeHelper", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"], linkerSettings: [.linkedFramework("SystemConfiguration")]),
    .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"])
], swiftLanguageVersions: [.v5])
