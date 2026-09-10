# NotchGate Testing Checklist

## Core Functionality
- [ ] App launches as menu bar extra (no Dock icon in production build)
- [ ] Notch overlay appears correctly on MacBook with Dynamic Island
- [ ] Notch overlay appears correctly on Mac without notch (centered at 120px)
- [ ] Collapsed bar shows shoulders with content
- [ ] Expanded flyout panel appears on hover/click
- [ ] Flyout panel dismisses when mouse leaves
- [ ] Animations work smoothly (expand/collapse)

## Widget Features (Pro features)
- [ ] CPU monitor displays correctly with sparkline
- [ ] Memory monitor displays correctly with sparkline
- [ ] Battery monitor shows charge percentage and charging status
- [ ] Disk monitor shows usage percentage
- [ ] Network monitor displays upload/download stats
- [ ] Process strip shows running apps
- [ ] Device strip shows connected devices
- [ ] Calendar widget shows next event (requires Calendar permission)
- [ ] Weather widget displays current weather (requires Location permission)
- [ ] Now Playing widget shows active music
- [ ] App Slots allow drag-and-drop app launching
- [ ] Drop Shelf stores dropped apps
- [ ] Pomodoro timer widget toggles window
- [ ] Search widget opens Spotlight search

## Settings & Customization
- [ ] Settings window opens via gear icon or Cmd+,
- [ ] Shoulder customization works (load/clock/status/network/search/pomodoro)
- [ ] Toggle monitoring widgets on/off
- [ ] Theme customization applies correctly
- [ ] Refresh interval adjusts update frequency
- [ ] Overlay level setting works (normal/screen saver)
- [ ] Fullscreen shoulder visibility toggle works

## Permission Checks (Critical for App Store)
- [ ] **NO** `NSScreenCaptureUsageDescription` in Info.plist
- [ ] **NO** `NSScreenRecordingUsageDescription` in Info.plist
- [ ] Calendar permission request appears when enabled (LSService)
- [ ] Location permission request appears when weather enabled (CLManager)
- [ ] No unexpected permission prompts on first launch
- [ ] App functions without Calendar/Location permissions (graceful fallback)

## Edge Cases
- [ ] App works on multi-monitor setups
- [ ] App handles Space/Workspace switching
- [ ] App stays below screen saver when enabled
- [ ] App minimizes gracefully when not hovering
- [ ] App persists settings across restarts
- [ ] App handles system restart gracefully
- [ ] App works with different macOS themes

## License & Pricing
- [ ] Free tier shows watermark/limitations
- [ ] Pro features locked without license
- [ ] Pricing window opens correctly
- [ ] Restore purchases works
- [ ] License validation functions properly

## Build Configuration
- [ ] `showsDockIcon = false` in release build (line 7-12 in NotchGateApp.swift)
- [ ] Menu bar extra style (`.menu`) instead of `.window`
- [ ] No debug flags like `--show-settings`, `--store-preview` in production
- [ ] App size is reasonable for App Store
- [ ] All entitlements are minimal and necessary

## App Store Review
- [ ] Privacy Policy explicitly states "We do not capture your screen"
- [ ] No screen recording functionality exists anywhere in code
- [ ] All data collection is opt-in (Calendar, Location)
- [ ] No third-party analytics or tracking
- [ ] In-app purchases properly configured
