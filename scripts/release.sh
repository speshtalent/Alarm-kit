#!/usr/bin/env bash

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/MyAlarmApp.xcarchive"
IPA_PATH="$BUILD_DIR/MyAlarmApp.ipa"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/ExportOptions.plist"

log() {
  printf '\n[release] %s\n' "$1"
}

cd "$ROOT_DIR"

log "Incrementing build number"
agvtool next-version -all

log "Cleaning previous builds"
rm -rf build

log "Archiving app"
xcodebuild \
  -project MyAlarmApp.xcodeproj \
  -scheme MyAlarmApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

log "Exporting IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

log "Uploading build to App Store Connect"
asc builds upload --app 6761073513 --ipa ./build/MyAlarmApp.ipa --wait

log "Release completed successfully"
