# NotchGate

NotchGate is a native macOS command-center overlay for Macs with a camera notch. It keeps useful status information and lightweight controls close to the menu bar without replacing macOS system UI.

## Product highlights

- Expandable notch overlay with CPU, memory, battery, disk, network, and status widgets.
- Calendar and local weather widgets with direct interaction inside the main panel.
- Pomodoro timer and HUDs.
- Native music controls that auto-detect Music.app or Spotify when either player is running.
- A sandboxed file shelf with Finder access and AirDrop sharing for user-selected files.
- Spotlight-style app search.
- Pinned app shortcuts with launch, reorder, replace, repair, and removal actions.
- Custom themes and layout settings.
- StoreKit non-consumable Pro upgrade with purchase restoration.

## Technical highlights

Native Xcode/macOS application with automated tests, local StoreKit configuration, privacy documentation, App Store metadata, and release-oriented scripts.

The app does not capture screenshots, enumerate active apps or connected devices, or install helper software. Music controls use explicit Apple Events automation for Music.app or Spotify, and file access is limited to items the user selects or drops into the shelf.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- An Apple Developer team for signed distribution builds

## Build locally

Open `NotchGate.xcodeproj`, select the **NotchGate** scheme, and run it on **My Mac**.

```sh
xcodebuild -project NotchGate.xcodeproj \\
  -scheme NotchGate \\
  -configuration Release \\
  -sdk macosx \\
  -derivedDataPath /tmp/NotchGateDerived \\
  build
```

The repository includes `NotchGate/Products.storekit` for local StoreKit testing. Create distribution archives through Xcode Organizer.

## Privacy and permissions

Calendar access is used for upcoming events. Location is used for local weather, with forecast requests sent to Open-Meteo. Search history and preferences remain on the Mac. StoreKit communicates with Apple to verify purchases. The in-app privacy policy is in `AppStore/PrivacyPolicy.html`.

The repository excludes signing credentials, build products, and distribution archives.

App Store listing and submission notes are in `AppStore/`.

## App shortcuts

- Click an empty slot to choose an installed application.
- Click a populated slot to launch it.
- Option-click or Command-click a slot to replace its app.
- Drag populated slots to reorder them.
- Right-click a slot to open, force quit, reveal, replace, or remove the shortcut.

Only installed application bundles and internal slot reordering are accepted as shortcut drops; arbitrary files and URLs are rejected.

## StoreKit

The Pro product identifier is `com.notchlens.pro` and is configured as a non-consumable purchase. Release builds use StoreKit entitlements as the source of truth. Users can restore an active purchase from the same Apple ID after reinstalling the app.

## Repository layout

- `NotchGate/` — macOS application source and resources
- `NotchGateTests/` — automated tests
- `AppStore/` — App Store Connect metadata, legal text, screenshots, and checklist
- `Icons/` and `IconExports/` — icon source and exported artwork
- `scripts/` — development utilities
