// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MeetingAssistant",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "MeetingAssistant", targets: ["MeetingAssistant"]),
    .library(name: "MeetingAssistantCore", targets: ["MeetingAssistantCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
  ],
  targets: [
    .target(
      name: "MeetingAssistantCore",
      dependencies: [
        .product(name: "WhisperKit", package: "WhisperKit")
      ],
      path: "Sources/MeetingAssistantCore",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    ),
    .executableTarget(
      name: "MeetingAssistant",
      dependencies: ["MeetingAssistantCore"],
      path: "Sources/MeetingAssistant",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    ),
    .testTarget(
      name: "MeetingAssistantTests",
      dependencies: ["MeetingAssistantCore"],
      path: "Tests/MeetingAssistantTests",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
