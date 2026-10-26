// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "AozoraEbooks",
	defaultLocalization: "en",
	platforms: [.macOS(.v15)],
	products: [
		.library(name: "AozoraKit", targets: ["AozoraKit"]),
		.executable(name: "aozora", targets: ["aozora"]),
	],
	dependencies: [
		.package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
		.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.8.0"),
	],
	targets: [
		.target(
			name: "AozoraKit",
			dependencies: ["CArchive", "ZIPFoundation", "SwiftSoup"],
			resources: [.copy("Resources"), .process("Localizable.xcstrings")]
		),
		.systemLibrary(name: "CArchive"),
		.executableTarget(name: "aozora", dependencies: ["AozoraKit"]),
		.testTarget(name: "AozoraKitTests", dependencies: ["AozoraKit"]),
	]
)
