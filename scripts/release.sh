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

usage() {
  cat <<'EOF'
Usage: release.sh [-m|--marketing-version <version>] [-h|--help]

  -m, --marketing-version <version>   Set the App Store / marketing version (e.g. 1.3)
                                      before bumping the build number. Uses agvtool
                                      new-marketing-version (updates CFBundleShortVersionString).

  -h, --help                          Show this help.

Without -m, only the build number is incremented (agvtool next-version), same as before.
EOF
}

MARKETING_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--marketing-version)
      [[ -n "${2:-}" ]] || die "Missing value for $1 (example: $1 1.3)"
      MARKETING_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[release] Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

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

if [[ -n "$MARKETING_VERSION" ]]; then
  log "Setting marketing version to $MARKETING_VERSION"
  agvtool new-marketing-version "$MARKETING_VERSION"
fi

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
if [[ -n "$MARKETING_VERSION" ]]; then
  git commit -m "Set marketing version to ${MARKETING_VERSION} and bump build after release"
else
  git commit -m "Bump build number after release"
fi

log "Pushing git changes"
git push

log "Release completed successfully"
