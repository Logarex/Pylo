// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Pylo", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "PyloCore", targets: ["PyloCore"]), .executable(name: "anfr-import", targets: ["ANFRImport"])], targets: [.systemLibrary(name: "CSQLite"), .target(name: "PyloCore", dependencies: ["CSQLite"]), .executableTarget(name: "ANFRImport", dependencies: ["PyloCore"], resources: [.process("Resources")]), .testTarget(name: "PyloCoreTests", dependencies: ["PyloCore"])])
