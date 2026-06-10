// swift-tools-version: 6.2

import PackageDescription

// The sidecar reuses the existing, already-tested native core by depending on the root
// SwiftPM package via a relative path. It links only the public capture and permission
// surface (PermissionCenter, SystemAudioCaptureService). Nothing in the root package is
// modified. The path dependency transitively links WhisperKit/CoreML because
// MeetingAssistantCore depends on it; Phase 1 never calls the transcriber.
let package = Package(
  name: "meetingcore-sidecar",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "meetingcore-sidecar",
      dependencies: [
        .product(name: "MeetingAssistantCore", package: "MeetingAssistant")
      ],
      path: "Sources/meetingcore-sidecar",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ],
      linkerSettings: [
        // Embed an Info.plist into the bare executable so this process carries the privacy
        // usage strings and a stable bundle identity for TCC. The path is resolved by the
        // linker relative to the package root. If the linker cannot find it, replace the
        // last argument with an absolute path to Info.plist.
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/meetingcore-sidecar/Info.plist"
        ])
      ]
    ),
    // Seam regression checks (Phase 2). These spawn the built sidecar binary and speak the
    // frozen NDJSON contract at it, plus a roundtrip check on the frozen recording.json
    // format using the core's own Codable types. Run with: swift build && swift test
    .testTarget(
      name: "SeamTests",
      dependencies: [
        .product(name: "MeetingAssistantCore", package: "MeetingAssistant")
      ],
      path: "Tests/SeamTests",
      resources: [
        .copy("Fixtures")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
