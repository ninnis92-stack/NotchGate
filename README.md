# NotchGate

NotchGate is a native macOS command-center overlay for Macs with a camera notch. It keeps useful status information and lightweight controls close to the menu bar without replacing macOS system UI.

## Product highlights

- Expandable overlay with CPU, memory, battery, disk, network, and status widgets.
- Calendar and local weather widgets.
- Pomodoro timer and heads-up displays.
- Spotlight-style app search.
- Pinned app shortcuts with launch, reorder, replace, repair, and removal actions.
- Custom themes and layout settings.
- StoreKit non-consumable Pro upgrade with purchase restoration.

## Technical highlights

Native Xcode/macOS application with automated tests, local StoreKit configuration, privacy documentation, App Store metadata, and release-oriented scripts.

The app deliberately avoids screenshot capture, arbitrary dropped files, active-app enumeration, device enumeration, cross-application automation, and helper installation.

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
