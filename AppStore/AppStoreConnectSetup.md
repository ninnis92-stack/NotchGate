# App Store Connect setup (NotchGate)

This is a click guide, not an in-app script. Do not add a `.swift` helper to the NotchGate target — it would ship inside the app.

## Identifiers
1. [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. App ID **Explicit**: `NotchLens.NotchGate`
3. Capability: In-App Purchase on

## App record
1. [App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → NotchGate
2. Platform macOS, SKU `notchgate`, bundle `NotchLens.NotchGate`

## In-App Purchase
1. Monetization → In-App Purchases → + → Non-Consumable
2. Reference name: NotchGate Pro
3. Product ID: **`com.notchlens.pro`** (must match `LicenseManager.productID`)
4. Price: United States $5.99
5. Localization en-US:
   - Display name: NotchGate Pro
   - Description: One-time unlock for calendar, weather, live network, disk and battery meters, and accent themes.
6. Submit with the app version (Ready to Submit)

## Version 1.0
1. App icon 1024 from `AppStore/NotchGateIcon_1024.png`
2. Screenshots: upload only current-feature screenshots; do not use captures of removed screenshot or file-drop features.
3. Description from `AppStore/AppStoreDescription.md`
4. Privacy policy URL: https://ninnis92-stack.github.io/notchgate-legal/
5. Support URL: https://ninnis92-stack.github.io/notchgate-legal/support.html
6. Replacement build 2 (capture features removed): `/tmp/NotchGate-1.0-build2.xcarchive`. Upload it, select build 2, attach IAP `com.notchlens.pro`, and resubmit for review.

## Review setup
When Pro is active, the app requests Calendar and Location permission only after the user interacts with the relevant widget. Prefaces use Continue, then the system prompt. No login or sample files are required. Music controls may request Apple Events permission when the user uses Music or Spotify controls; file sharing only operates on user-selected files.
