# NotchGate build 4 tracker

Status: **31 done / 25 still yours.** Do not upload until the “You still need to do” list is checked.

Local archive: `/tmp/NotchGate-1.0-build4-final.xcarchive`  
Store images: `AppStore/Upload-to-App-Store-Connect/`

Mark `[x]` as you finish an item.

---

## Done (verified in code, tests, or this Mac)

### Core
- [x] App launches with menu bar extra **and** Dock icon
- [x] Overlay appears on this notched MacBook
- [x] Collapsed bar shows shoulders with content
- [x] Expanded panel can appear (preview + hover path)

### Widgets
- [x] CPU sparkline
- [x] Memory sparkline
- [x] Battery percent / charging
- [x] Disk usage
- [x] Network up/down
- [x] Calendar next event (when access already granted)
- [x] Weather (when location already granted)
- [x] Now Playing
- [x] Drop shelf removed; normal files are rejected without crash

### Settings / license / review
- [x] Settings window opens (gear / Cmd+,)
- [x] No `NSScreenCaptureUsageDescription`
- [x] No `NSScreenRecordingUsageDescription`
- [x] Denied Calendar/Location still leave the app usable (empty/fallback copy)
- [x] Settings persist in UserDefaults / Keychain
- [x] Free vs Pro table (no watermark; Pro rows locked)
- [x] Pricing window opens
- [x] License product ID `com.notchlens.pro`; Debug unlocks Pro, Release does not
- [x] Dock icon on in Release (`showsDockIcon = true`, `LSUIElement = NO`)
- [x] Menu bar extra is `.menu`
- [x] `--show-settings` / `--store-preview` compiled out of Release
- [x] App size ~2.4 MB
- [x] Entitlements trimmed (sandbox, network, calendar, location, USB, Apple Events for Music/Spotify)
- [x] Privacy policy: “We do not capture your screen…” plus Open-Meteo
- [x] No screen recording / screenshot code
- [x] Calendar and Location are opt-in Pro features
- [x] No analytics / tracking SDKs

---

## You still need to do

Use the **Release** archive (or TestFlight), not a Debug Run. Debug always unlocks Pro.

### First launch / permissions
- [ ] **Free** first launch: no Calendar, Location, Bluetooth, Screen Recording, or Local Network prompts
- [ ] After unlocking Pro with Calendar on: EventKit permission dialog
- [ ] After unlocking Pro with Weather on: Location permission dialog
- [ ] Deny Calendar and Location: island still works; widgets show fallback, not a crash

### Core behavior
- [ ] Overlay on a **non-notched** display (centered fake cutout ~120px)
- [ ] Flyout dismisses when the pointer leaves
- [ ] Expand / collapse animation feels smooth
- [ ] Island **collapses** when you stop hovering (not Dock minimize)

### Widgets you should click through
- [ ] Process strip (Pro)
- [ ] Devices strip (Pro)
- [ ] Drag a real **.app** onto an app slot and launch it
- [ ] Pomodoro opens / toggles
- [ ] Search from the island (⌘⇧F if mapped)

### Settings
- [ ] Change left/right shoulders (load, clock, status, network, search, pomodoro)
- [ ] Toggle monitoring widgets on/off
- [ ] Pro theme accents (Midnight / Aurora / Ember / Glacier)
- [ ] Change stat refresh interval
- [ ] Overlay height: Menu bar vs Pop-up menu
- [ ] Full Screen shoulder visibility toggle

### Edge cases
- [ ] Laptop + external display; move pointer between them
- [ ] Spaces / Mission Control / Full Screen
- [ ] Screen saver and lock screen sit **above** the island
- [ ] Enable Open at Login, restart the Mac, island and settings still there
- [ ] macOS Light, Dark, and Auto (island stays dark; Settings follows system)

### Purchases (TestFlight / sandbox Apple ID)
- [ ] Restore Purchases on an Apple ID that already bought Pro
- [ ] Attach IAP `com.notchlens.pro` to version 1.0 in App Store Connect, then buy once on a sandbox account

When those 25 are checked, say so and we can upload build 4.
