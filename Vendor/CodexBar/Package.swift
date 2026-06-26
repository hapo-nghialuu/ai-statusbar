// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Vendored, trimmed copy of CodexBar's `CodexBarCore` library so BirdNion builds
// without the external ~/Desktop/CodexBar checkout. Only the CodexBarCore target
// (and its CSQLite3/remote deps) is kept — the CodexBar app/CLI/widget targets
// and their app-only dependencies (Sparkle, Vortex, KeyboardShortcuts, Commander)
// are dropped.

let sqlite3LibDir = ProcessInfo.processInfo.environment["CODEXBAR_SQLITE3_LIB_DIR"]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
let sqlite3LinkerSettings: [LinkerSetting] = if let sqlite3LibDir, !sqlite3LibDir.isEmpty {
    [.unsafeFlags(["-L\(sqlite3LibDir)"], .when(platforms: [.linux]))]
} else {
    []
}

let package = Package(
    name: "CodexBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CodexBarCore", targets: ["CodexBarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
        .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.4.1"),
    ],
    targets: [
        // Host pkg-config paths contaminate cross-musl links; the module map supplies sqlite3 linkage.
        .systemLibrary(
            name: "CSQLite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
            ]),
        .target(
            name: "CodexBarCore",
            dependencies: [
                .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: sqlite3LinkerSettings),
    ])
