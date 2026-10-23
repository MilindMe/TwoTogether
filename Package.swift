// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TwoTogether", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "HabitCore", targets: ["HabitCore"])], targets: [.target(name: "HabitCore"), .testTarget(name: "HabitCoreTests", dependencies: ["HabitCore"])])
