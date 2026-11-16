# SwipeWipe

A private, native SwiftUI media-review app using Apple's Photos and Vision frameworks.

## Current features

- Reviews photos, Live Photos, videos, and other media assets exposed by Photos.
- Default review order is oldest to newest; the setting can switch to newest to oldest.
- Keeps a rolling in-memory window of 30 PhotoKit assets while reviewing; the next three media assets are previewed in the layered photo deck behind the active card.
- Swipe right to keep; swipe left to queue for deletion.
- A persistent **Undo** button reverses the last Keep or Remove action, one step at a time, in strict last-in/first-out order. Up to 200 review actions are retained locally.
- Videos can be opened in an in-app player before deciding to keep or remove them.
- Delete Queue groups pending items by capture day. Each day is shown as a collage of at most four thumbnails; when more than four are queued, the fourth tile shows `+N`. Tapping the collage opens a sheet with all items for that day, including individual Undo actions.
- Undo one queued deletion or undo the whole deletion queue.
- Deletion delay: Direct Removal or 1–30 minutes. Direct Removal collects items for a single confirmation batch.
- Full Photos Access is required before the main interface is shown.
- Date filter and review order apply to photos and videos.
- Duplicate scan uses two methods:
  - **Exact duplicates:** SHA-256 of original PhotoKit resources, including videos.
  - **Visually similar photos:** Apple Vision `VNGenerateImageFeaturePrintRequest` feature prints and `VNFeaturePrintObservation.computeDistance`, filtered to photos captured within 60 seconds. The initial distance threshold is 0.35. Shorter Vision distances mean greater similarity, but this threshold is a heuristic and results must be reviewed before removal.
- Duplicate scan processes PhotoKit assets in batches of 30, hashes resources incrementally, and only feature-prints images with nearby capture times.
- Cyberpunk-inspired UI with persistent Dark/Light selection.
- Settings footer credits: “Developed with ❤️ by Alejandro Tidele” and links to https://atidele.dev.
- Original cyberpunk SwipeWipe app icon is preserved in the asset catalog.

## Run in Xcode

1. Open `SwipeWipe.xcodeproj` in Xcode.
2. Select the SwipeWipe app target and choose your Apple Development team in **Signing & Capabilities**.
3. Select an iPhone or simulator and press **Run**.
4. Grant Full Photos Access when prompted.

## Unit tests and CI

The repository includes a Swift Package target containing testable, Foundation-only business logic in `SwipeWipe/ReviewActionHistory.swift`. Run the tests locally from the repository root:

```bash
swift test
```

The tests cover:
- LIFO undo across Keep and Remove actions (including the Keep, Keep, Remove, Remove example)
- Restoring a previously kept item after undoing a later queue action
- Undo-history persistence, prior-state restoration, and its 200-action limit
- Discarding history for physically deleted assets
- Oldest-first default and newest-first option
- The 30-item chunk window and final partial chunk
- Showing up to three upcoming deck previews
- Skipping kept, visited, and pending items correctly
- Grouping queue items by calendar day
- The capture-time and Vision feature-distance similarity policy
- The four-tile queue collage and `+N` overflow calculation

GitHub Actions runs `swift test`, builds the iOS app for the Simulator with `xcodebuild`, and runs Xcode static analysis.

## Important behavior and limitations

### Undo history

Undo works one review action per tap, latest action first. It supports Keep and queued Remove gestures, including duplicate bulk-queue actions. The history is persisted locally and retains up to 200 actions. Once an item is physically deleted from Photos, its related undo records are discarded; SwipeWipe cannot restore a photo after the Photos deletion transaction has completed.

### Similarity detection

Vision feature prints describe image content and `computeDistance` compares two feature prints; lower distances indicate more similar images. SwipeWipe uses an initial threshold of 0.35 and only compares image assets captured within 60 seconds of one another. This combination is intended to find near-duplicate shots and burst-like captures, not to prove that two images are interchangeable. It can miss similar images taken farther apart and may surface visually similar but distinct shots. Always review suggested copies before queueing them. The threshold can be tuned after testing against a representative photo library.

The Vision scan uses locally available PhotoKit thumbnails (`isNetworkAccessAllowed = false`). iCloud-only photos may be skipped unless a local version is cached. Video exact matching is supported; visual similarity matching currently targets still-image assets.

### Deletion

iOS still presents its own confirmation for PhotoKit deletion operations. Direct Removal batches items until the user taps **Delete Now**. Delayed items are submitted when their deadline has passed and the app is active; iOS can suspend the app, so exact-time background deletion cannot be guaranteed. iOS may also keep deleted items in Recently Deleted according to Photos behavior.

### Photos permissions

PhotoKit requires read/write access to browse and delete items. SwipeWipe requires the `.authorized` (Full Access) state and blocks the main interface for Limited, Denied, or Restricted access.

## Build note

The Xcode project is configured for iOS 17+. Swift package tests can be run on macOS with `swift test`. The iOS app itself must be built and tested in Xcode with the iOS SDK and a Simulator/device.
