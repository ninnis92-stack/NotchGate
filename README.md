# NotchGate

NotchGate is a native macOS command-center overlay for Macs with a camera notch. It keeps useful status information and lightweight controls close to the menu bar without replacing macOS system UI.

## Features

- Expandable notch overlay with CPU, memory, battery, disk, network, and status widgets.
- Calendar and local weather widgets with direct interaction inside the main panel.
- Pomodoro timer and HUDs.
- Spotlight-style app search.
- Pinned app shortcuts that launch apps, support internal reordering, and provide repair/removal actions.
- Custom themes and layout settings for Pro users.
- StoreKit non-consumable Pro upgrade with purchase restoration through the user’s Apple ID.

The app does not capture screenshots, accept arbitrary dropped files, enumerate active apps or connected devices, automate other applications, or install helper software.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- An Apple Developer team for signed distribution builds

## Build locally

Open `NotchGate.xcodeproj` in Xcode, select the `NotchGate` scheme, and run it on **My Mac**. The repository includes `NotchGate/Products.storekit` for local StoreKit testing.

For a command-line build:

```sh
xcodebuild -project NotchGate.xcodeproj \
  -scheme NotchGate \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath /tmp/NotchGateDerived \
  build
```

For distribution, archive the app in Xcode and upload the signed archive through Organizer to App Store Connect.

## Permissions and privacy

NotchGate requests Calendar access only to show upcoming events and Location access only to retrieve local weather. Weather coordinates are sent to Open-Meteo to provide the forecast. Search history and preferences remain on the Mac. StoreKit communicates with Apple to verify purchases.

The in-app privacy policy is in `AppStore/PrivacyPolicy.html`. App Store listing and submission notes are in `AppStore/`.

## App shortcuts

- Click an empty slot to choose an installed application.
- Click a populated slot to launch it.
- Option-click or Command-click a slot to replace its app.
- Drag populated slots to reorder them.
- Right-click a slot to open, force quit, reveal, replace, or remove the shortcut.

External files and URLs are not accepted as shortcut drops. This keeps the shortcut feature scoped to installed applications and internal slot organization.

## StoreKit

The Pro product identifier is `com.notchlens.pro` and is configured as a non-consumable purchase. Release builds use StoreKit entitlements as the source of truth. Users can restore an active purchase from the same Apple ID after reinstalling the app.

## Repository layout

- `NotchGate/` — macOS application source and resources
- `NotchGateTests/` — automated tests
- `AppStore/` — App Store Connect metadata, legal text, screenshots, and checklist
- `Icons/` and `IconExports/` — icon source and exported artwork
- `scripts/` — development utilities
