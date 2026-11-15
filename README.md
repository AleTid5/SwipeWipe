# SwipeWipe

A private, native SwiftUI media-review app. It uses Apple's Photos framework and keeps review state on the device.

## Included functionality

- Reviews the user's Photos library, including photos, Live Photos, videos, and audio assets exposed by Photos.
- Default review order is **oldest to newest**. Settings lets the user switch to **newest to oldest**.
- Swipe right / Keep: marks an item as kept and removes it from the normal review flow.
- Swipe left / Delete: queues an item for deletion.
- Displays a preview strip of the next three eligible items to help the user review faster.
- Videos can be opened in an in-app video player before deciding whether to keep or delete them.
- Uses a rolling in-memory window of at most 30 `PHAsset` objects. The Photos fetch result is queried in chunks; the app does not materialize the whole library as an array.
- Duplicate scanning also processes assets in chunks of 30 rather than retaining all PhotoKit assets at once. Resource bytes are hashed incrementally to avoid buffering a full video in memory.
- Undo one queued deletion or undo the whole queue.
- Deletion delay setting: Direct removal or 1–30 minutes.
- Full Photos Access is required before the main app interface is shown; Limited Access is not accepted.
- Direct removal collects swiped items into a ready-to-delete batch. Tap **Delete Now** in the queue to submit them together in one Photos confirmation.
- Delayed removals whose deadlines are close together are coalesced in a 15-second window and submitted together in one PhotoKit change request.
- Date filter: only media created on or after the selected date is reviewed and scanned.
- “Show kept photos again”: previously kept items can appear once in a new review round.
- Exact duplicate scan based on SHA-256 hashes of original PhotoKit resources. It is byte-for-byte matching, not visual similarity matching.
- Duplicate groups preselect extra copies, allow manual selection, and support bulk queueing.
- Review state, settings, and pending deletion deadlines persist locally using UserDefaults.
- Settings footer credits: “Developed with ❤️ by Alejandro Tidele” and links to https://atidele.dev.
- Original cyberpunk SwipeWipe app icon is preserved in the asset catalog.

## Open and run on your iPhone

1. Open `SwipeWipe.xcodeproj` in Xcode on your Mac.
2. Select the **SwipeWipe** project, then its **SwipeWipe** target.
3. In **Signing & Capabilities**, select your Apple Account under **Team**. If necessary, change the bundle identifier from `com.example.swipewipe` to a unique value.
4. Connect your iPhone, unlock it, and trust the Mac if prompted.
5. Select your iPhone as the run destination and press **Run**.
6. On first launch, grant SwipeWipe **Full Access** to Photos. The main app is gated until Full Access is enabled. If you choose Limited Access or deny permission, the app shows an access screen with a shortcut to iPhone Settings. Set **Settings → SwipeWipe → Photos → Full Access**, then return and tap **Check access again**.

For personal installation, Xcode can sign the app with a free Apple Account. Free provisioning has a short validity period (commonly seven days), so you may need to run it from Xcode again to refresh the installation. A paid Apple Developer Program membership gives longer-lived development signing.

## Important behavior and limitations

### Chunked loading

The model holds no more than 30 `PHAsset` objects in its active review window. It fetches more assets when the user approaches the end of that window, keeping the current item and up to three next-item previews available. PhotoKit's `PHFetchResult` remains the query handle; the app does not convert the entire library into a 14,000-item in-memory array. Thumbnail images are requested only for the current item and the three preview tiles.

### Videos and other media

The library query does not restrict `mediaType`, so video assets are included alongside still images and Live Photos. Video items show their duration and can be opened in the built-in player. Audio assets exposed by Photos are represented with an audio waveform tile. iCloud video playback may require a network connection because playback allows PhotoKit to request the original when needed.

### Delayed deletion

The pending queue and deadlines are stored locally. While SwipeWipe is active, expired items are submitted to Photos for deletion. iOS can suspend an app while it is in the background, so this app cannot guarantee deletion at the exact deadline while it is closed. When the app becomes active again, overdue items are processed. This is a platform lifecycle limitation, not a server-side timer.

“Direct removal” adds each swiped item to a ready-to-delete batch instead of calling Photos once per swipe. Open **Delete queue** and tap **Delete Now** to submit the entire batch in one PhotoKit change request and receive one iOS confirmation for that batch. The app only removes the items after you confirm. The system's Photos behavior and Recently Deleted recovery still apply; this is not a secure erase operation.

For delayed removals, the app waits up to 15 seconds after the first item in a batch expires so items with nearby deadlines can be grouped into one PhotoKit change request. This means an automatic removal can happen up to 15 seconds after its selected delay, in addition to any delay caused by iOS suspending the app. iOS does not provide a way for an app to pre-approve those confirmations.

### Duplicate detection

The scanner detects byte-for-byte identical original PhotoKit resources, including video resources. It does not identify visually similar photos, resized/recompressed copies, burst shots, or near-duplicates. To avoid silently downloading large iCloud originals, the scan skips resources that aren't available locally and reports the skip count. Hashing is incremental and on-device.

### Photos permissions

PhotoKit requires read/write access to browse and delete items. SwipeWipe requires the `.authorized` (Full Access) state. It deliberately blocks the main interface when Photos access is `.limited`, `.denied`, or `.restricted`; users can change access in iOS Settings.

## Build note

The project is configured for iOS 17+. It was updated in this environment but cannot be compiled against Apple's iOS SDK here. Open it in Xcode and resolve any SDK/compiler diagnostics before relying on it with a real library. Test deletion first with a small set of non-important items.

## App icon

The project's original custom 1024 × 1024 cyberpunk-inspired SwipeWipe icon is preserved in `SwipeWipe/Assets.xcassets/AppIcon.appiconset`. Xcode compiles it as the iOS app icon.
