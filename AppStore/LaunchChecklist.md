# NotchGate launch checklist

Work top to bottom. Do not submit until Archive succeeds.

## Already in the Xcode project
- [x] Bundle ID `NotchLens.NotchGate`
- [x] Team `693AH4QR5Q` (Naheem Innis)
- [x] Apple Development signing (Debug Run)
- [x] App icon (gate + notch + camera) in `AppIcon.appiconset`
- [x] 1024 icon: `AppStore/NotchGateIcon_1024.png` (same as `IconExports/icon_1024.png`)
- [x] StoreKit product `com.notchlens.pro` in `Products.storekit` for local Debug
- [x] Privacy Nutrition file `PrivacyInfo.xcprivacy`
- [x] Encryption flag: uses non-exempt encryption = NO
- [x] Deployment macOS 14.0
- [x] App Sandbox **on** (calendar, location, network client, user-selected files, and Apple Events)
- [ ] Adversarial/unit tests after feature removal: `NotchGateTests` (Product → Test)

## App Store Connect
- [ ] Upload `AppStore/NotchGateIcon_1024.png` (no transparency)
- [ ] IAP `com.notchlens.pro`, Non-Consumable, $5.99, English localization — attach to version 1.0
- [ ] Paid Applications agreement, tax, banking
- [x] Privacy URL: https://ninnis92-stack.github.io/notchgate-legal/
- [x] Support URL: https://ninnis92-stack.github.io/notchgate-legal/support.html
- [ ] Paste those URLs plus copy from `AppStore/AppStoreDescription.md` into the 1.0 listing
- [ ] Screenshots: upload current-feature screenshots only (Mac 16:10); remove any old screenshot/file-drop imagery.
- [ ] Remove or replace previously uploaded screenshots that show removed features. The Pomodoro image remains accurate.
- [ ] Age rating, category Utilities
- [ ] After processing, select the uploaded build and Submit for Review

## Binary
- [ ] `Product → Run` on this Mac (sandboxed): island, hover, Full Screen, Pomodoro, HUD
- [ ] `Product → Test` after the feature removal
- [ ] `Product → Archive` the updated build
- [x] App Sandbox is **on**.
- [x] Upload to App Store Connect succeeded 2026-09-04 (`xcodebuild -exportArchive -allowProvisioningUpdates`)
- [ ] Remove or ignore the StoreKit config for Archive (scheme already uses it only on Run)

## Review notes (paste in App Store Connect)
NotchGate is a menu-bar accessory (`LSUIElement`) with an overlay at the camera notch. Hover the island to expand. Pro is a one-time IAP. Calendar and Weather are interactive directly in the main expanded panel; permissions are requested only after the user interacts with the relevant widget. Music controls use Apple Events only after the user enables the feature, and file sharing is limited to user-selected files.

## Do not submit until
Island hover is stable, Full Screen does not flicker, and you have a real privacy URL plus a signed Archive.
