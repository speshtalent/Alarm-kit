#!/usr/bin/env bash

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/MyAlarmApp.xcarchive"
IPA_PATH="$BUILD_DIR/MyAlarmApp.ipa"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/ExportOptions.plist"
VERSION_FILES=(
  "MyAlarmApp.xcodeproj/project.pbxproj"
  "MyAlarmApp/Info.plist"
  "CountdownLiveActivity/Info.plist"
  "FutureAlarmWidget/Info.plist"
)

log() {
  printf '\n[release] %s\n' "$1"
}

die() {
  printf '\n[release] ERROR: %s\n' "$1" >&2
  exit 1
}

is_version_file() {
  local file="$1"

  for version_file in "${VERSION_FILES[@]}"; do
    if [[ "$version_file" == "$file" ]]; then
      return 0
    fi
  done

  return 1
}

ensure_safe_git_state() {
  local line path has_changes=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    has_changes=1
    path="${line:3}"
    if ! is_version_file "$path"; then
      printf '[release] Unexpected git change: %s\n' "$path" >&2
      die "Working tree must be clean except for known build-number files."
    fi
  done < <(git status --porcelain)

  if [[ "$has_changes" -eq 0 ]]; then
    return 0
  fi
}

cd "$ROOT_DIR"

log "Checking git status"
ensure_safe_git_state

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

log "Committing build number changes"
git add "${VERSION_FILES[@]}"
if git diff --cached --quiet; then
  die "No version file changes were staged for commit."
fi
git commit -m "Bump build number after release"

log "Pushing git changes"
git push

log "Release completed successfully"
