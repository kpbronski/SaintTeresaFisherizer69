# CLAUDE.md - iOS SwiftUI Project Rules (Feb 2026)

## Environment
- Xcode 26.3+
- Swift 6.0+
- SwiftUI only (no UIKit unless requested)
- Deployment target: iOS 19.0+
- Claude Agent fully enabled

## Critical Rules (NEVER break these)

- Always use modern SwiftUI + Swift 6 concurrency (@Observable, @MainActor, async/await).
- Follow Apple HIG strictly.
- Every View must have a beautiful #Preview.
- Use MVVM or Observation pattern.
- Add accessibility labels and dark mode support by default.

## Folder Structure (create as needed)
- Models/
- Views/
- ViewModels/
- Services/
- Resources/Assets.xcassets
- Utilities/

Claude: You have full access to the codebase, SwiftUI Previews, builds, and tests. Be proactive, clean, and production-ready. Project name is "STB Fisherizer 69".
